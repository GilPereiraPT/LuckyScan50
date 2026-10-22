"""Validate local website links, anchors, accessibility basics and assets."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import xml.etree.ElementTree as ET

ROOT = Path('website').resolve()


class Page(HTMLParser):
    def __init__(self, filename):
        super().__init__(convert_charrefs=True)
        self.filename, self.ids, self.links = filename, set(), []
        self.h1, self.lang, self.has_title = 0, '', False

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'html':
            self.lang = attrs.get('lang')
        if tag == 'title':
            self.has_title = True
        if tag == 'h1':
            self.h1 += 1
        if 'id' in attrs:
            assert attrs['id'] not in self.ids, 'Duplicate HTML id'
            self.ids.add(attrs['id'])
        assert not any(key.lower().startswith('on') for key in attrs), 'Inline event handler'
        for key in ('href', 'src'):
            if attrs.get(key):
                self.links.append(attrs[key])
        if tag == 'img':
            assert 'alt' in attrs, 'Image without alt'
            assert 'width' in attrs and 'height' in attrs, 'Missing image dimensions'


pages = {}
for file in ROOT.glob('*.html'):
    parser = Page(file.name)
    parser.feed(file.read_text(encoding='utf-8'))
    assert parser.lang == 'pt-PT', 'Wrong page language'
    assert parser.h1 == 1 and parser.has_title, 'Missing/duplicate heading or title'
    pages[file.resolve()] = parser
assert len(pages) == 4
for file, page in pages.items():
    for link in page.links:
        url = urlsplit(link)
        assert url.scheme not in ('javascript', 'data'), 'Unexpected link scheme'
        if url.scheme or url.netloc:
            continue
        target = (file.parent / unquote(url.path or file.name)).resolve()
        assert target.is_relative_to(ROOT), 'Path escapes website'
        if target.is_dir():
            target /= 'index.html'
        assert target.is_file(), f'Broken local link in {file.name}: {link}'
        if url.fragment and target.suffix == '.html':
            assert url.fragment in pages[target].ids, f'Broken anchor: {link}'
for filename in ('logo.webp', 'banner.webp'):
    signature = (ROOT / 'assets' / filename).read_bytes()[:12]
    assert signature[:4] == b'RIFF' and signature[8:] == b'WEBP'
ET.parse(ROOT / 'sitemap.xml')
html = (ROOT / 'index.html').read_text()
assert 'Exemplo ilustrativo' in html and 'não uma captura da app' in html
assert 'releases/download/v0.2.8/LuckyScan50-0.2.8-arm64.apk' in html
assert not any(ROOT.rglob('*.sqlite*'))
print('PASS: 4 pages; local links, anchors, assets and accessibility basics.')
