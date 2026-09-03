#!/usr/bin/env bash
# bin/hwpx2md.py 테스트 — OWPML 구조를 흉내 낸 합성 HWPX 로 문단·줄바꿈·표 변환을 검증하고,
# .hwp 바이너리는 변환기 부재 시 exit 3 안내를 내는지 확인한다.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1: ${2:-}"; }
WORK=$(mktemp -d)

python3 - "$WORK/sample.hwpx" <<'PY'
import sys, zipfile
NS = 'xmlns:hp="http://www.hancom.co.kr/hwpml/2011/paragraph" xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section" xmlns:hc="http://www.hancom.co.kr/hwpml/2011/core"'
section = f'''<?xml version="1.0" encoding="UTF-8"?>
<hs:sec {NS}>
  <hp:p id="1"><hp:run><hp:t>홍길동 이력서</hp:t></hp:run></hp:p>
  <hp:p id="2"><hp:run><hp:t>백엔드 개발자 지원</hp:t><hp:lineBreak/><hp:t>Spring Boot | Redis</hp:t></hp:run></hp:p>
  <hp:p id="3"><hp:run><hp:tbl rowCnt="2" colCnt="2">
    <hp:tr><hp:tc><hp:subList><hp:p><hp:run><hp:t>회사</hp:t></hp:run></hp:p></hp:subList></hp:tc>
           <hp:tc><hp:subList><hp:p><hp:run><hp:t>기간</hp:t></hp:run></hp:p></hp:subList></hp:tc></hp:tr>
    <hp:tr><hp:tc><hp:subList><hp:p><hp:run><hp:t>플러스테크</hp:t></hp:run></hp:p></hp:subList></hp:tc>
           <hp:tc><hp:subList><hp:p><hp:run><hp:t>2025.01 ~ 2025.06</hp:t></hp:run></hp:p></hp:subList></hp:tc></hp:tr>
  </hp:tbl></hp:run></hp:p>
  <hp:p id="4"><hp:run><hp:t>응답시간 350ms → 15ms 단축</hp:t></hp:run></hp:p>
</hs:sec>'''
hpf = '''<?xml version="1.0" encoding="UTF-8"?>
<opf:package xmlns:opf="http://www.idpf.org/2007/opf/"><opf:manifest>
<opf:item id="header" href="Contents/header.xml" media-type="application/xml"/>
<opf:item id="section0" href="Contents/section0.xml" media-type="application/xml"/>
</opf:manifest><opf:spine><opf:itemref idref="header"/><opf:itemref idref="section0"/></opf:spine></opf:package>'''
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr('mimetype', 'application/hwp+zip')
    z.writestr('Contents/content.hpf', hpf)
    z.writestr('Contents/header.xml', '<?xml version="1.0"?><hh:head xmlns:hh="http://www.hancom.co.kr/hwpml/2011/head"/>')
    z.writestr('Contents/section0.xml', section)
PY

OUT=$(python3 "$REPO/bin/hwpx2md.py" "$WORK/sample.hwpx" 2>&1); RC=$?
[ $RC -eq 0 ] && ok "hwpx 변환 exit 0" || bad "hwpx 변환 exit" "rc=$RC $OUT"
grep -q '홍길동 이력서' <<<"$OUT" && ok "문단 텍스트" || bad "문단 텍스트" "$OUT"
grep -q '^Spring Boot | Redis' <<<"$OUT" && ok "lineBreak → 줄바꿈" || bad "lineBreak" "$OUT"
grep -q '^| 회사 | 기간 |' <<<"$OUT" && grep -q '^| 플러스테크 | 2025.01 ~ 2025.06 |' <<<"$OUT" && ok "표 → 마크다운 표" || bad "표" "$OUT"
grep -q 'tables=1' <<<"$OUT" && ok "통계 주석" || bad "통계 주석" "$OUT"
grep -q '350ms → 15ms' <<<"$OUT" && ok "표 뒤 문단 유지" || bad "표 뒤 문단" "$OUT"
# 표 셀 텍스트가 본문에 중복되지 않는지
[ "$(grep -c '플러스테크' <<<"$OUT")" -eq 1 ] && ok "표 셀 중복 없음" || bad "표 셀 중복" "$OUT"

# --out
python3 "$REPO/bin/hwpx2md.py" "$WORK/sample.hwpx" --out "$WORK/sample.md" >/dev/null && [ -s "$WORK/sample.md" ] && ok "--out 파일 출력" || bad "--out"

# .hwp (OLE) — 변환기 없음 → exit 3 + 안내
printf '\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1' > "$WORK/legacy.hwp"; head -c 600 /dev/zero >> "$WORK/legacy.hwp"
OUT=$(python3 "$REPO/bin/hwpx2md.py" "$WORK/legacy.hwp" --converter none 2>&1); RC=$?
[ $RC -eq 3 ] && grep -q 'HWPX' <<<"$OUT" && ok "hwp 변환기 부재 → exit 3 안내" || bad "hwp exit 3" "rc=$RC $OUT"

# 정체불명 파일
echo "plain" > "$WORK/x.bin"
python3 "$REPO/bin/hwpx2md.py" "$WORK/x.bin" >/dev/null 2>&1; [ $? -eq 1 ] && ok "비 HWP 파일 exit 1" || bad "비 HWP exit 1"

rm -rf "$WORK"
echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && { echo "[PASS] hwpx2md"; exit 0; } || { echo "[FAIL] hwpx2md"; exit 1; }
