#!/usr/bin/env bash
# Профилирование тестового набора GUT: точечный прогон каждого скрипта
# с замером wall-времени и junit-XML (чистое время, ассерты).
# Использование: tools/perf_gut.sh [имя1 имя2 ...]   (без аргументов — все)
# Результат: /tmp/perf/summary.tsv, junit в /tmp/perf/junit/, логи в /tmp/perf/logs/
set -u
cd "$(dirname "$0")/.."

OUT=/tmp/perf
mkdir -p "$OUT/junit" "$OUT/logs"

# Конфиг без dirs: скрипты задаются только через -gtest, иначе
# .gutconfig.json добавит весь каталог и запустится полный набор.
CONF="$OUT/gut_one.json"
if [ ! -f "$CONF" ]; then
	python3 - "$CONF" <<'EOF'
import json, sys
c = json.load(open('.gutconfig.json'))
c.pop('dirs', None)
json.dump(c, open(sys.argv[1], 'w'), indent=1)
EOF
fi

if [ "$#" -gt 0 ]; then
	SCRIPTS="$*"
else
	SCRIPTS=$(ls tests/test_*.gd | sed 's|^tests/||; s|\.gd$||')
fi

SUM="$OUT/summary.tsv"
[ -f "$SUM" ] || printf 'script\twall_s\tjunit_s\ttests\tfails\tstatus\n' > "$SUM"

for name in $SCRIPTS; do
	# уже замерено — пропускаем (продолжение прерванного прогона)
	if grep -q "^$name	" "$SUM"; then continue; fi
	t0=$(date +%s.%N)
	timeout 4800 godot --headless -s addons/gut/gut_cmdln.gd \
		-gconfig="$CONF" -gtest="res://tests/$name.gd" \
		-gjunit_xml_file="$OUT/junit/$name.xml" \
		> "$OUT/logs/$name.log" 2>&1
	rc=$?
	t1=$(date +%s.%N)
	wall=$(python3 -c "print(f'{$t1-$t0:.1f}')")
	junit_s=$(python3 -c "
import xml.etree.ElementTree as ET, sys
try:
	r = ET.parse('$OUT/junit/$name.xml').getroot()
	s = r.find('testsuite')
	print(f\"{float(s.get('time')):.1f}\t{s.get('tests')}\t{s.get('failures')}\")
except Exception as e:
	print('?\t?\t?')" 2>/dev/null)
	printf '%s\t%s\t%s\t%s\n' "$name" "$wall" "$junit_s" "$rc" >> "$SUM"
done
echo DONE >> "$SUM"
