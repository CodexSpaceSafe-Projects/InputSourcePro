import contextlib
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import ci_xcodebuild as ci


class XcodeDiagnosticsTests(unittest.TestCase):
    def test_swift_error_has_file_line_and_column(self):
        self.assertEqual(ci.parse_diagnostic('/workspace/My App/View.swift:21:7: error: missing return'),
                         ci.Diagnostic('missing return', '/workspace/My App/View.swift', '21', '7'))

    def test_xctest_error_without_column(self):
        self.assertEqual(ci.parse_diagnostic('/src/Tests.swift:42: error: -[Test check] : XCTAssert failed'),
                         ci.Diagnostic('-[Test check] : XCTAssert failed', '/src/Tests.swift', '42'))

    def test_general_errors_and_failed_cases_are_reported(self):
        self.assertEqual(ci.parse_diagnostic('xcodebuild: error: Unable to find a destination').message,
                         'Unable to find a destination')
        self.assertIsNotNone(ci.parse_diagnostic("Test Case '-[Tests testExample]' failed (0.1 seconds)."))
        self.assertIsNone(ci.parse_diagnostic('** TEST FAILED **'))
        self.assertIsNone(ci.parse_diagnostic('/src/Main.swift:2:4: warning: unused value'))

    def test_annotations_escape_actions_control_characters(self):
        diagnostic = ci.Diagnostic('bad%\r\n::warning::text', '/src/A,B:File.swift', '2', '4')
        self.assertEqual(ci.annotation(diagnostic),
                         '::error file=/src/A%2CB%3AFile.swift,line=2,col=4::bad%25%0D%0A::warning::text')

    def test_workspace_paths_are_relative_and_ansi_is_removed(self):
        diagnostic = ci.parse_diagnostic('\x1b[31m/src/App.swift:1:2: error: invalid\x1b[0m')
        with patch.dict(os.environ, GITHUB_WORKSPACE='/src'):
            self.assertEqual(ci.annotation(diagnostic), '::error file=App.swift,line=1,col=2::invalid')

    def test_command_exit_status_and_log_are_preserved_and_errors_deduplicated(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'build.log'
            summary = Path(directory) / 'summary.md'
            code = "import sys; print('/src/File.swift:8:9: error: invalid'); print('/src/File.swift:8:9: error: invalid'); sys.exit(65)"
            captured = io.StringIO()
            with contextlib.redirect_stdout(captured), patch.dict(os.environ, GITHUB_STEP_SUMMARY=str(summary)):
                status = ci.execute([sys.executable, '-c', code], log)
            self.assertEqual(status, 65)
            self.assertEqual(captured.getvalue().count('::error '), 1)
            self.assertEqual(log.read_text().count('error: invalid'), 2)
            self.assertIn('exited 65', summary.read_text())

    def test_success_does_not_emit_error_annotations(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()) as captured:
            self.assertEqual(ci.execute([sys.executable, '-c', "print('done')"], Path(directory) / 'build.log'), 0)
            self.assertNotIn('::error', captured.getvalue())

    def test_annotation_count_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()) as captured:
            code = "import sys; [print(f'/src/File.swift:{i+1}:1: error: invalid {i}') for i in range(40)]; sys.exit(1)"
            self.assertEqual(ci.execute([sys.executable, '-c', code], Path(directory) / 'build.log'), 1)
            self.assertEqual(captured.getvalue().count('::error '), 30)


if __name__ == '__main__':
    unittest.main()
