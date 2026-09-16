#!/usr/bin/env python3
"""Regenerate the legal docs from the app's copy — run from the repo root.

    python3 legal/make_legal_pages.py

LegalContent.swift is the SINGLE SOURCE. This writes legal/*.md (keeping the
dev-only reviewer banner) and docs/*.html (banner stripped — never publish it).
There used to be three hand-maintained copies and they drifted: the live privacy
page still said "Tadah has no accounts and no sign-in" months after accounts
shipped. Always edit LegalContent.swift, then run this, then deploy:

    npx wrangler pages deploy docs --project-name tadah-legal --branch main

(tadah-legal.pages.dev is the live site; cuevi-legal is the old pre-rename copy.)
"""
import re, html, os

src = open('Tadah/Tadah/App/LegalContent.swift').read()

def extract(name):
    m = re.search(r'static let %s = #"""\n(.*?)\n"""#' % name, src, re.S)
    return m.group(1)

BANNER = """> ⚠️ **Template — not legal advice.** This draft reflects how Tadah actually
> handles data today, but you should have a lawyer review it before a paid or
> public App Store launch, especially because Tadah touches tax, immigration,
> insurance, medical, and legal topics. Fill in every **[BRACKETED]** placeholder.
"""

def to_md(body):
    """Insert the dev-only banner after the date line (the in-app copy strips it)."""
    lines = body.split('\n')
    for i, l in enumerate(lines):
        if l.startswith('**Effective date:**'):
            # split the combined date line back into two, md-style
            l2 = l.replace(' **Last updated:**', '\n**Last updated:**')
            lines[i:i+1] = l2.split('\n')
            lines.insert(i + 2, '\n' + BANNER)
            break
    return '\n'.join(lines) + '\n'

def md_to_html(md, title):
    out, in_ul, in_tbl = [], False, False
    def inline(t):
        t = html.escape(t, quote=True).replace('&#x27;', "'")
        t = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', t)
        t = re.sub(r'(?<!\*)\*([^*]+?)\*(?!\*)', r'<em>\1</em>', t)
        t = re.sub(r'\[(.+?)\]\((.+?)\)', r'<a href="\2">\1</a>', t)
        t = re.sub(r'<(https?://[^>]+)>', r'<a href="\1">\1</a>', t)
        return t
    for raw in md.split('\n'):
        line = raw.rstrip()
        if line.startswith('|'):
            cells = [c.strip() for c in line.strip('|').split('|')]
            if set(''.join(cells)) <= set('-: '):
                continue
            if not in_tbl:
                out.append('<table>'); in_tbl = True
                out.append('<tr>' + ''.join(f'<th>{inline(c)}</th>' for c in cells) + '</tr>')
            else:
                out.append('<tr>' + ''.join(f'<td>{inline(c)}</td>' for c in cells) + '</tr>')
            continue
        if in_tbl:
            out.append('</table>'); in_tbl = False
        if line.startswith('- '):
            if not in_ul: out.append('<ul>'); in_ul = True
            out.append(f'<li>{inline(line[2:])}</li>'); continue
        if in_ul and not line.startswith('- '):
            out.append('</ul>'); in_ul = False
        if not line: continue
        if line.startswith('### '):  out.append(f'<h3>{inline(line[4:])}</h3>')
        elif line.startswith('## '): out.append(f'<h2>{inline(line[3:])}</h2>')
        elif line.startswith('# '):  out.append(f'<h1>{inline(line[2:])}</h1>')
        elif line.startswith('> '):  continue                    # dev-only note: never publish
        elif line.strip() == '---':  out.append('<hr>')
        else: out.append(f'<p>{inline(line)}</p>')
    if in_ul:  out.append('</ul>')
    if in_tbl: out.append('</table>')
    style = ("body{max-width:760px;margin:2rem auto;padding:0 1rem;font:16px/1.6 -apple-system,Segoe UI,Roboto,"
             "sans-serif;color:#29261b;background:#f7f5f1}h1{font-size:1.9rem}h2{margin-top:1.8rem}"
             "code{background:#eee;padding:.1em .3em;border-radius:3px}table{border-collapse:collapse;width:100%}"
             "td,th{border:1px solid #ccc;padding:.4em .6em;text-align:left;vertical-align:top}a{color:#b14a2a}"
             "hr{border:none;border-top:1px solid #ddd;margin:1.5rem 0}")
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8">\n'
            '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
            f'<title>{title}</title>\n<style>{style}</style></head><body>\n'
            + '\n'.join(out) + '\n</body></html>\n')

for swift_name, md_path, html_path, title in [
    ('privacyPolicy', 'legal/privacy-policy.md',   'docs/privacy.html', 'Tadah — Privacy Policy'),
    ('terms',         'legal/terms-of-service.md', 'docs/terms.html',   'Tadah — Terms of Service'),
]:
    body = extract(swift_name)
    open(md_path, 'w').write(to_md(body))
    open(html_path, 'w').write(md_to_html(body, title))
    print(f"wrote {md_path} + {html_path}")
