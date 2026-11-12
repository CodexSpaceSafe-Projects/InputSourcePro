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
                                    GITHUB_EVENT_NAME='workflow_dispatch',
                                    GITHUB_SHA=self.git('rev-parse', 'HEAD'),
                                    GITHUB_REPOSITORY='example/offline-app',
                                    GITHUB_OUTPUT=str(Path('output').resolve()))
        self.variables.start()
        self.addCleanup(self.variables.stop)

    def git(self, *args):
        return subprocess.check_output(['git', *args], text=True, stderr=subprocess.DEVNULL).strip()

    def github(self, *responses):
        original = release.run
        values = iter(responses)

        def respond(*args):
            return json.dumps(next(values)) if args[0] == 'gh' else original(*args)

        return patch.object(release, 'run', side_effect=respond)

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

    def test_main_push_automatically_releases_a_new_version(self):
        self.git('tag', '2.12.0')
        with patch.dict(os.environ, GITHUB_EVENT_NAME='push'):
            metadata = release.prepare()
        self.assertTrue(metadata['publish'])
        self.assertEqual(metadata['tag'], '2.13.0')
        self.assertEqual(metadata['version'], '2.13.0')
        self.assertFalse(Path('dist/notes.md').exists(), 'Missing notes must not block publication')

    def test_first_main_version_can_release_without_existing_tags(self):
        with patch.dict(os.environ, GITHUB_EVENT_NAME='push'):
            self.assertTrue(release.prepare()['publish'])

    def test_existing_equivalent_or_newer_tags_prevent_main_republication(self):
        for tag in ['2.13.0', 'v2.13.0', '2.14.0']:
            with self.subTest(tag=tag):
                self.git('tag', tag)
                with patch.dict(os.environ, GITHUB_EVENT_NAME='push'):
                    metadata = release.prepare()
                self.assertFalse(metadata['publish'])
                self.assertEqual(metadata['tag'], '')
                self.git('tag', '-d', tag)

    def test_feature_pushes_and_pull_requests_cannot_release(self):
        for event, ref in [('push', 'refs/heads/feature'), ('pull_request', 'refs/heads/main'),
                           ('pull_request', 'refs/pull/1/merge'), ('workflow_dispatch', 'refs/heads/main')]:
            with self.subTest(event=event, ref=ref), patch.dict(os.environ, GITHUB_EVENT_NAME=event, GITHUB_REF=ref):
                self.assertFalse(release.prepare()['publish'])

    def test_project_version_must_be_numeric_and_consistent(self):
        for project in ['MARKETING_VERSION = v2.13.0;', 'MARKETING_VERSION = 2.13;',
                        'MARKETING_VERSION = 2.13.0;\nMARKETING_VERSION = 2.14.0;', '']:
            with self.subTest(project=project):
                Path('Input Source Pro.xcodeproj/project.pbxproj').write_text(project)
                with self.assertRaisesRegex(ValueError, 'MARKETING_VERSION'):
                    release.prepare()

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
        path.write_text('Committed release notes\n')
        self.git('add', str(path))
        self.git('commit', '-qm', 'release notes')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        with patch.dict(os.environ, GITHUB_SHA=self.git('rev-parse', 'HEAD')):
            self.git('tag', 'v2.14.0')
            path.write_text('Uncommitted changes')
            with patch.dict(os.environ, GITHUB_REF='refs/tags/v2.14.0'):
                release.prepare()
        self.assertEqual(Path('dist/notes.md').read_text(), 'Committed release notes\n')

    def test_restoring_notes_preserves_release_decision_after_tag_creation(self):
        path = Path('docs/release-notes/2.13.0.md')
        path.parent.mkdir(parents=True)
        path.write_text('New version\n')
        self.git('add', str(path))
        self.git('commit', '-qm', 'notes')
        self.git('update-ref', 'refs/remotes/origin/main', 'HEAD')
        with patch.dict(os.environ, GITHUB_SHA=self.git('rev-parse', 'HEAD'), GITHUB_EVENT_NAME='push'):
            metadata = self.packaged()
            self.git('tag', metadata['tag'])
            Path('dist/notes.md').unlink()
            release.notes()
        self.assertEqual(json.loads(Path('dist/release.json').read_text()), metadata)
        self.assertTrue(metadata['publish'])
        self.assertEqual(Path('dist/notes.md').read_text(), 'New version\n')

    def test_artifact_must_belong_to_event_commit(self):
        self.tagged()
        self.packaged()
        self.git('commit', '--allow-empty', '-qm', 'different source')
        with patch.dict(os.environ, GITHUB_SHA=self.git('rev-parse', 'HEAD')):
            with self.assertRaisesRegex(ValueError, 'event commit'):
                release.publish()

    def test_artifact_tag_must_match_version(self):
        metadata = self.tagged()
        metadata['tag'] = '2.15.0'
        Path('dist/release.json').write_text(json.dumps(metadata))
        with self.assertRaisesRegex(ValueError, 'artifact version'):
            release.notes()

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
        with self.assertRaisesRegex(ValueError, 'Only release builds'):
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
        with self.github(existing):
            with self.assertRaisesRegex(ValueError, 'already published'):
                release.publish()

    def test_newer_release_blocks_old_tag(self):
        self.tagged()
        self.packaged()
        existing = [[dict(tag_name='2.15.0', draft=False, prerelease=False)]]
        with self.github(existing):
            with self.assertRaisesRegex(ValueError, 'newer version'):
                release.publish()

    def test_metadata_cannot_publish_to_another_repository(self):
        self.tagged()
        self.packaged()
        with patch.dict(os.environ, GITHUB_REPOSITORY='other/repository'):
            with self.assertRaisesRegex(ValueError, 'different repository'):
                release.publish()

    def test_publisher_creates_missing_tag_at_the_tested_commit(self):
        metadata = self.tagged()
        target = dict(type='commit', sha=metadata['commit'])
        with patch.object(release, 'read_tag', side_effect=[None, target]), \
                patch.object(release.subprocess, 'run') as commands:
            release.ensure_tag(metadata)
        command = commands.call_args.args[0]
        self.assertIn('ref=refs/tags/' + metadata['tag'], command)
        self.assertIn('sha=' + metadata['commit'], command)

    def test_publisher_preserves_a_matching_existing_tag(self):
        metadata = self.tagged()
        with patch.object(release, 'read_tag', return_value=dict(type='commit', sha=metadata['commit'])), \
                patch.object(release.subprocess, 'run') as commands:
            release.ensure_tag(metadata)
        commands.assert_not_called()

    def test_publisher_never_moves_a_tag_for_another_commit(self):
        metadata = self.tagged()
        with patch.object(release, 'read_tag', return_value=dict(type='commit', sha='0' * 40)), \
                patch.object(release.subprocess, 'run') as commands:
            with self.assertRaisesRegex(ValueError, 'tested commit'):
                release.ensure_tag(metadata)
        commands.assert_not_called()

    def test_annotated_tag_is_resolved_to_the_tested_commit(self):
        metadata = self.tagged()
        with patch.object(release, 'read_tag', return_value=dict(type='tag', sha='a' * 40)), \
                self.github(dict(object=dict(type='commit', sha=metadata['commit']))):
            release.ensure_tag(metadata)

    def test_tag_read_only_treats_404_as_missing(self):
        for code in [403, 404, 500]:
            with self.subTest(code=code), patch.object(release.subprocess, 'run', return_value=
                    subprocess.CompletedProcess([], 1, '', f'gh: Request failed (HTTP {code})')):
                if code == 404:
                    self.assertIsNone(release.read_tag('2.14.0'))
                else:
                    with self.assertRaises(subprocess.CalledProcessError):
                        release.read_tag('2.14.0')

    def test_verified_assets_are_uploaded_before_release_becomes_public(self):
        metadata = self.tagged()
        self.packaged()
        assets = [Path('dist', metadata['asset']), Path('dist', metadata['asset'] + '.sha256')]
        uploaded = dict(assets=[dict(name=path.name, size=path.stat().st_size,
                                    digest='sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()) for path in assets])
        draft = [[dict(tag_name=metadata['tag'], id=42, draft=True)]]
        original = subprocess.run

        def execute(command, *args, **kwargs):
            if command[0] == 'gh':
                return subprocess.CompletedProcess(command, 0)
            return original(command, *args, **kwargs)

        with self.github([], draft, uploaded), patch.object(release, 'ensure_tag'), \
                patch.object(release.subprocess, 'run', side_effect=execute) as commands:
            release.publish()
        operations = [call.args[0] for call in commands.call_args_list if call.args[0][0] == 'gh']
        self.assertEqual([command[2] for command in operations], ['create', 'upload', 'edit'])
        self.assertIn('--draft', operations[0])
        self.assertTrue(all(str(path) in operations[1] for path in assets))
        self.assertIn('--draft=false', operations[-1])

    def test_upload_digest_mismatch_keeps_release_private(self):
        metadata = self.tagged()
        self.packaged()
        draft = [[dict(tag_name=metadata['tag'], id=42, draft=True)]]
        original = subprocess.run

        def execute(command, *args, **kwargs):
            return subprocess.CompletedProcess(command, 0) if command[0] == 'gh' else original(command, *args, **kwargs)

        with self.github([], draft, dict(assets=[])), patch.object(release, 'ensure_tag'), \
                patch.object(release.subprocess, 'run', side_effect=execute) as commands:
            with self.assertRaisesRegex(ValueError, 'asset failed verification'):
                release.publish()
        operations = [call.args[0] for call in commands.call_args_list if call.args[0][0] == 'gh']
        self.assertFalse(any(command[2] == 'edit' for command in operations))


if __name__ == '__main__':
    unittest.main()
