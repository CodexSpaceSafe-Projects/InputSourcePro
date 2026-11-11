#!/usr/bin/env python3
"""Validate and publish dependency-free macOS ZIP releases to this repository."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess

VERSION = re.compile(r'v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\Z')
REPOSITORY = re.compile(r'[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?/[A-Za-z0-9_.-]+\Z')
OFFSET = 1000


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def git(*args):
    return run('git', *args)


def version_tuple(tag):
    match = VERSION.fullmatch(tag)
    return tuple(map(int, match.groups())) if match else None


def build_number(commit):
    if git('rev-parse', '--is-shallow-repository') != 'false':
        raise ValueError('Release builds require full Git history')
    return OFFSET + int(git('rev-list', '--count', commit))


def repository():
    value = os.environ.get('GITHUB_REPOSITORY', '')
    if not REPOSITORY.fullmatch(value) or value.rsplit('/', 1)[-1] in {'.', '..'}:
        raise ValueError('GITHUB_REPOSITORY must name the current owner/repository')
    return value


def prepare(_args=None):
    commit = git('rev-parse', f'{os.environ["GITHUB_SHA"]}^{{commit}}')
    ref = os.environ['GITHUB_REF']
    publish = ref.startswith('refs/tags/')
    if publish:
        tag = ref.removeprefix('refs/tags/')
        if version_tuple(tag) is None:
            raise ValueError('Release tags must have the form v1.2.3 or 1.2.3')
        if git('rev-parse', f'{ref}^{{commit}}') != commit:
            raise ValueError('Release tag does not point to the event commit')
        subprocess.run(['git', 'merge-base', '--is-ancestor', commit, 'origin/main'], check=True)
        version = tag.removeprefix('v')
    else:
        tag = ''
        project = Path('Input Source Pro.xcodeproj/project.pbxproj').read_text()
        match = re.search(r'MARKETING_VERSION = ([0-9.]+);', project)
        if not match or version_tuple(match.group(1)) is None:
            raise ValueError('Project MARKETING_VERSION must be a numeric version')
        version = match.group(1)
    metadata = dict(repository=repository(), commit=commit, version=version,
                    build=build_number(commit), tag=tag, publish=publish,
                    asset=f'Input-Source-Pro-{version}-macOS-universal.zip')
    Path('dist').mkdir(exist_ok=True)
    Path('dist/release.json').write_text(json.dumps(metadata, indent=2) + '\n')
    Path('dist/notes.md').unlink(missing_ok=True)
    if publish:
        # Only use notes committed with the selected version; never generate a changelog.
        path = f'docs/release-notes/{version}.md'
        if git('ls-tree', '--name-only', commit, '--', path):
            notes = subprocess.check_output(['git', 'show', f'{commit}:{path}'], text=True)
            if not notes.strip():
                raise ValueError(f'Release notes must not be empty: {path}')
            Path('dist/notes.md').write_text(notes)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for key, value in metadata.items():
            output.write(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n')
    return metadata


def check_bundle(args):
    metadata = json.loads(Path('dist/release.json').read_text())
    bundle = Path(args.bundle)
    info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
    expected = {'CFBundleVersion': str(metadata['build']),
                'CFBundleShortVersionString': metadata['version']}
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f'Built app has an unexpected {key}')
    if any(key.startswith(('SU', 'SPU')) for key in info):
        raise ValueError('Built app still contains automatic updater configuration')
    if 'CFBundleURLTypes' in info:
        raise ValueError('Built app still registers custom URL handlers')
    for relative in ['Contents/MacOS/Input Source Pro',
                     'Contents/Helpers/CaretPalette/setup',
                     'Contents/Helpers/CaretPalette/ISP Palette Control.app/Contents/MacOS/CaretControl']:
        if not (bundle / relative).is_file():
            raise ValueError(f'Built app is missing {relative}')


def checksum(_args=None):
    metadata = json.loads(Path('dist/release.json').read_text())
    asset = Path('dist') / metadata['asset']
    digest = hashlib.sha256(asset.read_bytes()).hexdigest()
    Path(str(asset) + '.sha256').write_text(f'{digest}  {asset.name}\n')
    return digest


def publish(_args=None):
    metadata = json.loads(Path('dist/release.json').read_text())
    if not metadata['publish'] or not metadata['tag']:
        raise ValueError('Only version-tag builds may publish releases')
    if metadata['repository'] != repository():
        raise ValueError('Release metadata belongs to a different repository')
    tag = metadata['tag']
    assets = [Path('dist') / metadata['asset'], Path('dist') / (metadata['asset'] + '.sha256')]
    expected_checksum = f'{hashlib.sha256(assets[0].read_bytes()).hexdigest()}  {assets[0].name}\n'
    if assets[1].read_text() != expected_checksum:
        raise ValueError('ZIP checksum does not match its checksum file')
    pages = json.loads(run('gh', 'api', '--paginate', '--slurp',
                           f'repos/{repository()}/releases?per_page=100'))
    releases = [item for page in pages for item in page]
    existing = next((item for item in releases if item['tag_name'] == tag), None)
    if existing and not existing['draft']:
        raise ValueError('This release is already published; its assets will not be overwritten')
    for item in releases:
        previous = version_tuple(item['tag_name'])
        if not item['draft'] and not item['prerelease'] and previous and previous >= version_tuple(tag):
            raise ValueError('A release with the same or a newer version already exists')
    if not existing:
        notes = ['--notes-file', 'dist/notes.md'] if Path('dist/notes.md').is_file() else ['--notes', '']
        subprocess.run(['gh', 'release', 'create', tag, '--repo', repository(), '--verify-tag',
                        '--draft', '--target', metadata['commit'], '--title', metadata['version'], *notes], check=True)
    subprocess.run(['gh', 'release', 'upload', tag, '--repo', repository(),
                    '--clobber', *map(str, assets)], check=True)
    current_pages = json.loads(run('gh', 'api', '--paginate', '--slurp',
                                   f'repos/{repository()}/releases?per_page=100'))
    draft = next(item for page in current_pages for item in page if item['tag_name'] == tag)
    uploaded = json.loads(run('gh', 'api', f'repos/{repository()}/releases/{draft["id"]}'))
    for path in assets:
        uploaded_asset = next((item for item in uploaded['assets'] if item['name'] == path.name), None)
        digest = 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()
        if not uploaded_asset or uploaded_asset['size'] != path.stat().st_size or uploaded_asset.get('digest') != digest:
            raise ValueError(f'Uploaded asset failed verification: {path.name}')
    subprocess.run(['gh', 'release', 'edit', tag, '--repo', repository(),
                    '--draft=false', '--latest=true'], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['prepare', 'check-bundle', 'checksum', 'publish'])
    parser.add_argument('--bundle', default='dist/Input Source Pro.app')
    arguments = parser.parse_args()
    {'prepare': prepare, 'check-bundle': check_bundle,
     'checksum': checksum, 'publish': publish}[arguments.command](arguments)
