import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        previous = os.getcwd()
        os.chdir(directory.name)
        self.addCleanup(directory.cleanup)
        self.addCleanup(os.chdir, previous)
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Release tests')
        self.git('config', 'user.email', 'release@example.com')
        Path('Input Source Pro.xcodeproj').mkdir()
        Path('Input Source Pro.xcodeproj/project.pbxproj').write_text('MARKETING_VERSION = 2.13.0;')
        self.git('add', '.')
        self.git('commit', '-qm', 'initial')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        self.variables = patch.dict(os.environ, GITHUB_REF='refs/heads/main',
                                    GITHUB_SHA=self.git('rev-parse', 'HEAD'),
                                    GITHUB_REPOSITORY='example/offline-app',
                                    GITHUB_OUTPUT=str(Path('output').resolve()))
        self.variables.start()
        self.addCleanup(self.variables.stop)

    def git(self, *args):
        return subprocess.check_output(['git', *args], text=True, stderr=subprocess.DEVNULL).strip()

    def tagged(self, tag='v2.14.0'):
        self.git('tag', tag)
        os.environ['GITHUB_REF'] = 'refs/tags/' + tag
        return release.prepare()

    def packaged(self):
        metadata = release.prepare()
        Path('dist', metadata['asset']).write_bytes(b'test archive')
        release.checksum()
        return metadata

    def bundle(self):
        metadata = release.prepare()
        app = Path('dist/Input Source Pro.app')
        resources = ['Contents/MacOS/Input Source Pro', 'Contents/Helpers/CaretPalette/setup',
                     'Contents/Helpers/CaretPalette/ISP Palette Control.app/Contents/MacOS/CaretControl']
        for relative in resources:
            target = app / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b'executable fixture')
        info = dict(CFBundleVersion=str(metadata['build']), CFBundleShortVersionString=metadata['version'])
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        return app, info

    def test_numeric_version_validation(self):
        for tag in ['1.2.3', 'v1.2.3', '0.0.1']:
            self.assertIsNotNone(release.version_tuple(tag))
        for tag in ['v01.2.3', '1.2', '1.2.3-beta', '1.2.3\n', '1.2.3;cmd']:
            self.assertIsNone(release.version_tuple(tag))

    def test_branch_builds_do_not_publish(self):
        with patch.dict(os.environ, GITHUB_REF='refs/heads/feature/offline'):
            metadata = release.prepare()
        self.assertFalse(metadata['publish'])
        self.assertEqual(metadata['tag'], '')
        self.assertEqual(metadata['repository'], 'example/offline-app')
        self.assertEqual(metadata['version'], '2.13.0')
        self.assertIn('publish=false', Path('output').read_text())
        self.assertFalse(Path('dist/notes.md').exists())

    def test_numeric_tags_set_release_version(self):
        for tag in ['2.14.0', 'v2.14.0']:
            metadata = self.tagged(tag)
            self.assertTrue(metadata['publish'])
            self.assertEqual(metadata['version'], '2.14.0')
            self.assertEqual(metadata['tag'], tag)

    def test_invalid_tag_is_rejected(self):
        with patch.dict(os.environ, GITHUB_REF='refs/tags/v2.14.0-beta'):
            with self.assertRaisesRegex(ValueError, 'Release tags'):
                release.prepare()

    def test_event_commit_must_match_tag(self):
        self.git('tag', '2.14.0')
        self.git('commit', '--allow-empty', '-qm', 'next')
        with patch.dict(os.environ, GITHUB_REF='refs/tags/2.14.0', GITHUB_SHA=self.git('rev-parse', 'HEAD')):
            with self.assertRaisesRegex(ValueError, 'event commit'):
                release.prepare()

    def test_tag_must_be_on_main(self):
        self.git('checkout', '-qb', 'feature')
        self.git('commit', '--allow-empty', '-qm', 'unmerged')
        with patch.dict(os.environ, GITHUB_SHA=self.git('rev-parse', 'HEAD')):
            with self.assertRaises(subprocess.CalledProcessError):
                self.tagged()

    def test_repository_must_come_from_valid_runtime_metadata(self):
        for value in ['', '../bad', 'owner/repo/extra', 'https://github.com/owner/repo']:
            with patch.dict(os.environ, GITHUB_REPOSITORY=value):
                with self.assertRaisesRegex(ValueError, 'GITHUB_REPOSITORY'):
                    release.prepare()

    def test_full_history_is_required(self):
        with patch.object(release, 'git', return_value='true'):
            with self.assertRaisesRegex(ValueError, 'full Git history'):
                release.build_number('HEAD')

    def test_tag_uses_only_committed_notes_without_rendering(self):
        path = Path('docs/release-notes/2.14.0.md')
        path.parent.mkdir(parents=True)
        path.write_text('Approved release notes\n')
        self.git('add', str(path))
        self.git('commit', '-qm', 'approved notes')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        with patch.dict(os.environ, GITHUB_SHA=self.git('rev-parse', 'HEAD')):
            self.git('tag', 'v2.14.0')
            path.write_text('Uncommitted changes')
            with patch.dict(os.environ, GITHUB_REF='refs/tags/v2.14.0'):
                release.prepare()
        self.assertEqual(Path('dist/notes.md').read_text(), 'Approved release notes\n')

    def test_checksum_matches_archive(self):
        metadata = self.packaged()
        checksum = Path('dist', metadata['asset'] + '.sha256').read_text()
        self.assertEqual(checksum, hashlib.sha256(b'test archive').hexdigest() + '  ' + metadata['asset'] + '\n')

    def test_valid_bundle_has_helpers_and_offline_metadata(self):
        app, _ = self.bundle()
        release.check_bundle(argparse.Namespace(bundle=str(app)))

    def test_bundle_rejects_wrong_version_updater_and_url_handler(self):
        app, original = self.bundle()
        for change in [dict(CFBundleVersion='0'), dict(SUFeedURL='https://example.invalid'), dict(CFBundleURLTypes=[])]:
            with self.subTest(change=change):
                (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(original | change))
                with self.assertRaises(ValueError):
                    release.check_bundle(argparse.Namespace(bundle=str(app)))

    def test_bundle_requires_native_helper_executables(self):
        app, _ = self.bundle()
        (app / 'Contents/Helpers/CaretPalette/setup').unlink()
        with self.assertRaisesRegex(ValueError, 'missing'):
            release.check_bundle(argparse.Namespace(bundle=str(app)))

    def test_branch_cannot_publish(self):
        self.packaged()
        with self.assertRaisesRegex(ValueError, 'version-tag'):
            release.publish()

    def test_corrupt_archive_is_not_uploaded(self):
        metadata = self.tagged()
        self.packaged()
        Path('dist', metadata['asset']).write_bytes(b'changed archive')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            release.publish()

    def test_existing_published_release_is_never_overwritten(self):
        self.tagged()
        self.packaged()
        existing = [[dict(tag_name='v2.14.0', draft=False, prerelease=False)]]
        with patch.object(release, 'run', return_value=json.dumps(existing)):
            with self.assertRaisesRegex(ValueError, 'already published'):
                release.publish()

    def test_newer_release_blocks_old_tag(self):
        self.tagged()
        self.packaged()
        existing = [[dict(tag_name='2.15.0', draft=False, prerelease=False)]]
        with patch.object(release, 'run', return_value=json.dumps(existing)):
            with self.assertRaisesRegex(ValueError, 'newer version'):
                release.publish()

    def test_metadata_cannot_publish_to_another_repository(self):
        self.tagged()
        self.packaged()
        with patch.dict(os.environ, GITHUB_REPOSITORY='other/repository'):
            with self.assertRaisesRegex(ValueError, 'different repository'):
                release.publish()


if __name__ == '__main__':
    unittest.main()
