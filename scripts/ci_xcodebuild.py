#!/usr/bin/env python3
"""Stream an Xcode command, preserve its status, and annotate useful diagnostics."""
import argparse
from collections import deque
from dataclasses import dataclass
import os
from pathlib import Path
import re
import subprocess
import sys

ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
LOCATION_ERROR = re.compile(r'^(?P<file>.+?):(?P<line>\d+)(?::(?P<column>\d+))?:\s*(?:fatal )?error:\s*(?P<message>.+)$')
GENERAL_ERROR = re.compile(r'^(?:[^\n]*?:\s*)?(?:fatal )?error:\s*(?P<message>.+)$')
TEST_FAILURE = re.compile(r"^Test Case .+ (?:failed|crashed)(?:\s|\.).*$")
MAX_ANNOTATIONS = 30


@dataclass(frozen=True)
class Diagnostic:
    message: str
    file: str = ''
    line: str = ''
    column: str = ''


def parse_diagnostic(line):
    clean = ANSI.sub('', line).strip()
    match = LOCATION_ERROR.match(clean)
    if match:
        return Diagnostic(match['message'], match['file'], match['line'], match['column'] or '')
    match = GENERAL_ERROR.match(clean)
    if match:
        return Diagnostic(match['message'])
    if TEST_FAILURE.match(clean):
        return Diagnostic(clean)
    return None


def escape(value, property_value=False):
    escaped = value.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    if property_value:
        escaped = escaped.replace(':', '%3A').replace(',', '%2C')
    return escaped


def annotation(diagnostic):
    properties = []
    if diagnostic.file:
        filename = diagnostic.file
        workspace = os.environ.get('GITHUB_WORKSPACE')
        if workspace:
            try:
                filename = str(Path(filename).relative_to(workspace))
            except ValueError:
                pass
        properties.append('file=' + escape(filename, property_value=True))
    if diagnostic.line:
        properties.append('line=' + diagnostic.line)
    if diagnostic.column:
        properties.append('col=' + diagnostic.column)
    fields = ' ' + ','.join(properties) if properties else ''
    return f'::error{fields}::{escape(diagnostic.message)}'


def write_summary(command, returncode, log_path, diagnostics):
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if not summary:
        return
    with open(summary, 'a') as output:
        output.write(f'\n### {Path(command[0]).name} exited {returncode}\n\n')
        output.write(f'Full output: `{log_path.name}` in the failure diagnostics artifact.\n\n')
        for diagnostic in diagnostics:
            location = ':'.join(value for value in [diagnostic.file, diagnostic.line, diagnostic.column] if value)
            output.write('    ' + (location + ': ' if location else '') + diagnostic.message.replace('\n', '\n    ') + '\n\n')


def execute(command, log_path):
    log_path.parent.mkdir(parents=True, exist_ok=True)
    diagnostics = []
    seen = set()
    tail = deque(maxlen=15)
    with log_path.open('w') as output:
        try:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, errors='replace', bufsize=1)
        except OSError as error:
            diagnostic = Diagnostic(f'Could not start {command[0]}: {error}')
            print(annotation(diagnostic), flush=True)
            output.write(diagnostic.message + '\n')
            write_summary(command, 127, log_path, [diagnostic])
            return 127
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            output.write(line)
            clean = ANSI.sub('', line).strip()
            if clean:
                tail.append(clean[:1200])
            diagnostic = parse_diagnostic(line)
            if diagnostic and diagnostic not in seen:
                seen.add(diagnostic)
                if len(diagnostics) < MAX_ANNOTATIONS:
                    diagnostics.append(diagnostic)
        process.stdout.close()
        returncode = process.wait()
    if returncode:
        if not diagnostics:
            context = '\n'.join(tail) if tail else '(no output)'
            diagnostics.append(Diagnostic(f'{Path(command[0]).name} failed with exit status {returncode}. Last output:\n{context}'))
        for diagnostic in diagnostics:
            print(annotation(diagnostic), flush=True)
        if len(seen) > MAX_ANNOTATIONS:
            print(f'Additional diagnostics omitted from annotations; full output is in {log_path.name}.', flush=True)
    write_summary(command, returncode, log_path, diagnostics)
    # Shell exit conventions preserve termination by signal as 128 + signal.
    return returncode if returncode >= 0 else 128 - returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    command = arguments.command
    if command and command[0] == '--':
        command = command[1:]
    if not command:
        parser.error('a command is required after --')
    return execute(command, arguments.log)


if __name__ == '__main__':
    sys.exit(main())
