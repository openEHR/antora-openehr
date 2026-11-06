#!/usr/bin/env python3
"""Check the class_* attributes in resources/global-vars.yml against the specification repos.

A class's anchor is on the page that includes its partial, `include::ROOT:partial$classes/<name>.adoc[]`,
directly or through a module partial. An xref without a version goes to the latest version of a
component, so each repo is read at its newest `release/*` branch (local branch first, else
`origin/release/*`). The attribute for a partial is `class_` and the partial name with dots as
underscores (`aom2.c_object` -> `class_aom2_c_object`), the name bmm-publisher links through.

Reported:
  wrong    an entry for an included partial that resolves to another page or anchor
  missing  an included partial with no entry
A suggested entry follows each, using a page_* attribute when one names the page. Entries pinned to
a version (`Release-1.0.4@...`) and entries for classes no page includes are not checked.

usage: scripts/check-class-map.py [--repos DIR] [--vars FILE]
  --repos  directory holding the specifications-* clones (default: repos)
  --vars   the attributes file (default: resources/global-vars.yml)
exit status 1 when an entry is wrong or missing.
"""
import argparse
import os
import re
import subprocess
import sys

ENTRY_RE = re.compile(r'^([A-Za-z0-9_-]+):\s*"(.*)"\s*$')
INCLUDE_RE = re.compile(r'^include::(?:([\w.-]+):)?partial\$([^\[]+)\[', re.M)
HEADING_RE = re.compile(r'^=+ (\S+) (Class|Enumeration|Interface)\s*$')


def git(repo, *args):
    return subprocess.run(['git', '-C', repo, *args], capture_output=True, text=True, check=True).stdout


def latest_release(repo):
    """Newest release/* branch of a repo, local first, or None."""
    for pattern in ('refs/heads/release/', 'refs/remotes/origin/release/'):
        refs = git(repo, 'for-each-ref', '--format=%(refname:short)', pattern).split()
        versions = [(tuple(int(n) for n in ref.rsplit('/', 1)[1].split('.')), ref)
                    for ref in refs if re.search(r'/\d+(\.\d+)*$', ref)]
        if versions:
            return max(versions)[1]
    return None


def included_classes(repo, ref, component):
    """{partial name: (anchor, [page ids that include it])} for one component at one ref."""
    paths = set(git(repo, 'ls-tree', '-r', '--name-only', ref, 'modules/').split())
    cache = {}

    def read(path):
        if path not in cache:
            cache[path] = git(repo, 'show', f'{ref}:{path}')
        return cache[path]

    classes = {}

    def walk(path, module, page, seen):
        if path in seen or path not in paths:
            return
        seen.add(path)
        for include_module, target in INCLUDE_RE.findall(read(path)):
            module_of_target = include_module or module
            partial = f'modules/{module_of_target}/partials/{target}'
            if partial.startswith('modules/ROOT/partials/classes/') and partial in paths:
                lines = read(partial).lstrip().splitlines()
                heading = HEADING_RE.match(lines[0]) if lines else None
                if heading:
                    name = partial.rsplit('/', 1)[1][:-len('.adoc')]
                    anchor = f'_{heading.group(1).lower()}_{heading.group(2).lower()}'
                    classes.setdefault(name, (anchor, []))[1].append(page)
            walk(partial, module_of_target, page, seen)

    for path in sorted(paths):
        m = re.match(r'modules/([^/]+)/pages/(.+\.adoc)$', path)
        if m:
            walk(path, m.group(1), f'{component}:{m.group(1)}:{m.group(2)}', set())
    return classes


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n', 1)[0])
    parser.add_argument('--repos', default='repos')
    parser.add_argument('--vars', default='resources/global-vars.yml')
    args = parser.parse_args()

    entries = {}
    with open(args.vars, encoding='utf-8') as f:
        for line in f:
            m = ENTRY_RE.match(line)
            if m:
                entries[m.group(1)] = m.group(2)

    def resolve(value, depth=0):
        return re.sub(r'\{([A-Za-z0-9_-]+)\}',
                      lambda m: resolve(entries[m.group(1)], depth + 1)
                      if m.group(1) in entries and depth < 10 else m.group(0), value)

    page_attributes = {}
    for name, value in entries.items():
        if name.startswith('page_'):
            page_attributes.setdefault(value, name)

    classes = {}
    checked = []
    for repo_name in sorted(os.listdir(args.repos)):
        repo = os.path.join(args.repos, repo_name)
        if not repo_name.startswith('specifications-') or not os.path.isdir(os.path.join(repo, '.git')):
            continue
        ref = latest_release(repo)
        descriptor = subprocess.run(['git', '-C', repo, 'show', f'{ref}:antora.yml'], capture_output=True, text=True)
        if ref is None or descriptor.returncode != 0:
            continue  # no release yet, or the release is not migrated to the Antora layout
        component = descriptor.stdout.split('name:', 1)[1].split()[0]
        found = included_classes(repo, ref, component)
        if found:
            checked.append(f'{component} {ref}')
        # A partial included by two components (RM 1.1.0 and BASE both document RESOURCE_DESCRIPTION) may go to either.
        for name, (anchor, pages) in found.items():
            classes.setdefault(f'class_{name.replace(".", "_")}', []).extend(f'{page}#{anchor}' for page in pages)

    wrong = missing = 0
    for attribute, wanted in sorted(classes.items()):
        page, anchor = wanted[0].split('#')
        page_ref = '{' + page_attributes[page] + '}' if page in page_attributes else page
        suggestion = f'{attribute}: "{page_ref}#{anchor}"'
        if attribute not in entries:
            missing += 1
            print(f'missing  {suggestion}')
        elif '@' not in resolve(entries[attribute]).split('#', 1)[0] and resolve(entries[attribute]) not in wanted:
            wrong += 1
            print(f'wrong    {attribute}: "{entries[attribute]}"\n      -> {suggestion}')

    print(f'{wrong} wrong, {missing} missing; checked {len(classes)} included classes in {", ".join(checked)}')
    return 1 if wrong or missing else 0


if __name__ == '__main__':
    sys.exit(main())
