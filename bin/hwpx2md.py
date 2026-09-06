#!/usr/bin/env python3
"""hwpx2md.py — 한글 문서(.hwpx / .hwp)를 마크다운 텍스트로 변환 (U-11).

- .hwpx (OWPML, KS X 6101): zip 안의 Contents/section*.xml 을 표준 라이브러리만으로 읽는다.
  문단 → 줄, 표 → 마크다운 표, 줄바꿈/탭 보존. 이미지·도형은 건너뛴다(개수만 보고).
- .hwp (5.x 바이너리): 외부 변환기(kordoc 또는 rhwp)가 있으면 호출하고, 없으면 exit 3 과 함께
  "한글에서 HWPX 로 저장" 안내를 낸다. pyhwp 는 채택하지 않는다(2020년 이후 미갱신, Python ≤3.8).
  npx 로 kordoc 을 내려받아 실행하는 것은 명시 opt-in(JOBSTACK_ALLOW_NPX=1) 일 때만, 고정 버전
  (JOBSTACK_KORDOC_SPEC, 기본 kordoc@4.12.3) 으로 호출한다 — 기본값으로 npm 레지스트리의 최신 패키지를
  실행하면 공급망 변조에 노출된다(PR #17 리뷰 반영).

사용법:
  hwpx2md.py <입력.hwpx|입력.hwp> [--out <출력.md>] [--converter auto|kordoc|rhwp|none]
종료 코드: 0 성공 · 1 입력 오류 · 2 파싱 실패(문서 크기 상한 초과 포함) · 3 .hwp 변환기 없음
  인자 오류(필수 인자 누락·잘못된 --converter 값 등)는 argparse 기본값대로 exit 2 를 낸다.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

HWP5_SIGNATURE = b'HWP Document File'
OLE_MAGIC = b'\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1'

MAX_ENTRY_BYTES = 20 * 1024 * 1024    # zip 항목 1개당 상한(20MB)
MAX_ARCHIVE_BYTES = 50 * 1024 * 1024  # 아카이브 전체 합계 상한(50MB) — 압축폭탄 방지
_READ_CHUNK = 1024 * 1024


class DocumentTooLarge(Exception):
    """zip 항목/아카이브 크기 상한 초과. main() 이 '[오류] 문서가 너무 큽니다' exit 2 로 처리."""


def _check_archive_size(zf: zipfile.ZipFile) -> None:
    """선언된 file_size(중앙 디렉터리 메타데이터)로 먼저 걸러낸다 — 실제로 압축을 풀기
    전에 극단적인 압축률의 zip bomb 을 차단한다."""
    total = 0
    for info in zf.infolist():
        if info.file_size > MAX_ENTRY_BYTES:
            raise DocumentTooLarge(info.filename)
        total += info.file_size
        if total > MAX_ARCHIVE_BYTES:
            raise DocumentTooLarge(info.filename)


def _read_limited(zf: zipfile.ZipFile, name: str) -> bytes:
    """zf.open() 으로 스트리밍 읽기 — 헤더의 file_size 가 위조돼 있어도(선언값과 실제
    압축 해제 바이트가 다른 경우) 누적 바이트가 상한을 넘는 순간 중단한다
    (_check_archive_size 와의 이중 방어)."""
    chunks = []
    total = 0
    with zf.open(name) as fh:
        while True:
            chunk = fh.read(_READ_CHUNK)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_ENTRY_BYTES:
                raise DocumentTooLarge(name)
            chunks.append(chunk)
    return b''.join(chunks)


def local(tag: str) -> str:
    return tag.rsplit('}', 1)[-1] if isinstance(tag, str) else ''


def section_files(zf: zipfile.ZipFile) -> list[str]:
    """content.hpf 의 spine 순서, 없으면 section 번호 순."""
    names = zf.namelist()
    sections = [n for n in names if re.match(r'^Contents/section\d+\.xml$', n)]
    hpf = next((n for n in names if n.lower().endswith('content.hpf')), None)
    if hpf:
        try:
            root = ET.fromstring(_read_limited(zf, hpf))
            items = {}
            for el in root.iter():
                if local(el.tag) == 'item' and el.get('id') and el.get('href'):
                    items[el.get('id')] = el.get('href')
            ordered = []
            for el in root.iter():
                if local(el.tag) == 'itemref' and el.get('idref') in items:
                    href = items[el.get('idref')]
                    cand = href if href in names else ('Contents/' + href if 'Contents/' + href in names else None)
                    if cand and re.search(r'section\d+\.xml$', cand):
                        ordered.append(cand)
            if ordered:
                return ordered
        except ET.ParseError:
            pass
    return sorted(sections, key=lambda n: int(re.search(r'(\d+)\.xml$', n).group(1)))


def run_text(el: ET.Element) -> str:
    """hp:t / lineBreak / tab 만 모아 텍스트로. 표(tbl)는 별도 렌더링하므로 제외."""
    out = []

    def walk(node: ET.Element):
        for child in node:
            name = local(child.tag)
            if name == 'tbl':
                continue
            if name == 't':
                out.append(''.join(child.itertext()))
            elif name == 'lineBreak':
                out.append('\n')
            elif name == 'tab':
                out.append('\t')
            else:
                walk(child)

    walk(el)
    return ''.join(out)


def cell_text(tc: ET.Element) -> str:
    parts = []
    for p in tc.iter():
        if local(p.tag) == 'p':
            t = run_text(p).strip()
            if t:
                parts.append(t)
    return ' '.join(parts).replace('|', '\\|').replace('\n', '<br>')


def render_table(tbl: ET.Element) -> list[str]:
    rows = []
    for tr in tbl:  # 직계 자식만 — tbl.iter() 는 중첩 표의 tr 까지 끌어와 바깥 표 행이 부풀려진다
        if local(tr.tag) != 'tr':
            continue
        cells = [cell_text(tc) for tc in tr if local(tc.tag) == 'tc']
        if cells:
            rows.append(cells)
    if not rows:
        return []
    width = max(len(r) for r in rows)
    rows = [r + [''] * (width - len(r)) for r in rows]
    lines = ['| ' + ' | '.join(rows[0]) + ' |', '|' + '---|' * width]
    lines += ['| ' + ' | '.join(r) + ' |' for r in rows[1:]]
    return lines


def render_section(xml_bytes: bytes, stats: dict) -> list[str]:
    root = ET.fromstring(xml_bytes)
    lines: list[str] = []
    for p in root:
        if local(p.tag) != 'p':
            continue
        text = run_text(p)
        text = re.sub(r'[ \t]+\n', '\n', text).strip('\n')
        if text.strip():
            lines.append(text)
            lines.append('')
        for tbl in [e for e in p.iter() if local(e.tag) == 'tbl']:
            # 중첩 표는 바깥 표의 셀 텍스트로 이미 흡수됐으므로 최상위 표만
            if any(local(a.tag) == 'tbl' for a in _ancestors(p, tbl)):
                continue
            t = render_table(tbl)
            if t:
                stats['tables'] += 1
                lines.extend(t)
                lines.append('')
        stats['pictures'] += sum(1 for e in p.iter() if local(e.tag) in ('pic', 'picture'))
    return lines


def _ancestors(root: ET.Element, target: ET.Element) -> list[ET.Element]:
    parent_map = {c: p for p in root.iter() for c in p}
    chain = []
    cur = parent_map.get(target)
    while cur is not None:
        chain.append(cur)
        cur = parent_map.get(cur)
    return chain


def convert_hwpx(path: str) -> tuple[str, dict]:
    stats = {'sections': 0, 'tables': 0, 'pictures': 0}
    with zipfile.ZipFile(path) as zf:
        _check_archive_size(zf)
        out: list[str] = []
        for name in section_files(zf):
            stats['sections'] += 1
            out.extend(render_section(_read_limited(zf, name), stats))
    text = '\n'.join(out).strip() + '\n'
    return text, stats


KORDOC_SPEC_DEFAULT = 'kordoc@4.12.3'   # npx 자동 실행 시 고정 버전(2026-09-05 npm latest) — 공급망 변조 완화


def npx_allowed() -> bool:
    """원격 패키지 자동 실행은 명시 opt-in 만 허용한다(기본 꺼짐, PR #17 리뷰 반영)."""
    return os.environ.get('JOBSTACK_ALLOW_NPX', '0') == '1'


def convert_hwp(path: str, converter: str) -> str:
    order = ['kordoc', 'rhwp'] if converter == 'auto' else [converter]
    kordoc_spec = os.environ.get('JOBSTACK_KORDOC_SPEC', KORDOC_SPEC_DEFAULT)
    for tool in order:
        if tool == 'kordoc' and shutil.which('kordoc'):
            r = subprocess.run(['kordoc', path], capture_output=True, text=True, timeout=180)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout
        if tool == 'kordoc' and npx_allowed() and shutil.which('npx'):
            # 사용자가 명시적으로 허용한 경우에만, 버전을 고정해 호출한다.
            r = subprocess.run(['npx', '-y', kordoc_spec, path], capture_output=True, text=True, timeout=300)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout
        if tool == 'rhwp' and shutil.which('rhwp'):
            r = subprocess.run(['rhwp', 'dump', path], capture_output=True, text=True, timeout=180)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout
    raise SystemExit(3)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog='hwpx2md.py', description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('input')
    p.add_argument('--out')
    p.add_argument('--converter', default='auto', choices=['auto', 'kordoc', 'rhwp', 'none'])
    a = p.parse_args(argv)

    if not os.path.isfile(a.input):
        print(f'[오류] 파일이 없습니다: {a.input}', file=sys.stderr)
        return 1
    with open(a.input, 'rb') as f:
        head = f.read(8)
    try:
        if zipfile.is_zipfile(a.input):
            text, stats = convert_hwpx(a.input)
            note = f"<!-- hwpx2md: sections={stats['sections']} tables={stats['tables']} pictures_skipped={stats['pictures']} -->\n"
            text = note + text
        elif head == OLE_MAGIC:
            if a.converter == 'none':
                raise SystemExit(3)
            text = convert_hwp(a.input, a.converter)
        else:
            print('[오류] HWPX(zip) 도 HWP 5.x(OLE) 도 아닙니다', file=sys.stderr)
            return 1
    except SystemExit as e:
        if e.code == 3:
            print('[안내] .hwp 바이너리를 변환할 도구(kordoc 또는 rhwp)가 없습니다. 한글에서 "다른 이름으로 저장 → HWPX" 로 '
                  '저장해 다시 올려주시거나, `npm i -g kordoc` 후 재시도하세요. npx 로 자동 실행하려면 '
                  f'JOBSTACK_ALLOW_NPX=1 을 명시하세요({KORDOC_SPEC_DEFAULT} 고정, JOBSTACK_KORDOC_SPEC 으로 변경).',
                  file=sys.stderr)
            return 3
        raise
    except DocumentTooLarge:
        print('[오류] 문서가 너무 큽니다', file=sys.stderr)
        return 2
    except (zipfile.BadZipFile, ET.ParseError, KeyError, RecursionError) as e:
        # RecursionError: 비정상적으로 깊게 중첩된 XML(run_text 의 walk() 가 재귀) —
        # 트레이스백 대신 파싱 실패로 정규화한다.
        print(f'[오류] 파싱 실패: {e}', file=sys.stderr)
        return 2

    if a.out:
        with open(a.out, 'w', encoding='utf-8') as f:
            f.write(text)
        print(a.out)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
