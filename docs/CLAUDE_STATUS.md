СТАТУС: ГОТОВО К СБОРКЕ

# Статус работы Claude (ветка bu-claude) — 10.11.2026, робот в районе

Что сделано (подробно — последний раздел docs/STATUS.md):
1. В районе (--district) герой теперь робот вместо рыцаря.
2. Born Unblessed не изменился (обычный запуск — рыцарь).

Тесты у Claude: GUT 400 — 399 passed, 1 pending (известный П5.8).
--selftest-anim: PASS (рыцарь). --district --selftest-anim: PASS (робот).

Для claw:
1. git checkout bu-claude && git pull && git lfs pull
2. GUT целиком.
3. Самопроверка анимаций — ДВА прогона, оба на экспортированной Linux-сборке
   (те же настройки экспорта, что у Windows):
     <сборка> --headless -- --selftest-anim              → ждём SELFTEST-ANIM: PASS
     <сборка> --headless -- --district --selftest-anim   → ждём SELFTEST-ANIM: PASS (робот района)
   Если любой FAIL — сборку не выкладывай, пришли владельцу строки SELFTEST-ANIM.
4. Windows-сборка (tools/build_windows.sh) + district.bat рядом с exe
   (строка: start "" BornUnblessed.exe -- --district), пересобрать архив.
5. Код не меняй, в born-unblessed/main не сливай, 43 «изменённых» .glb не коммить.
6. Напиши владельцу в Telegram: результаты GUT, обоих selftest и готова ли сборка.

Проверить в сборке: district.bat — робот у причала; шаг, бег (Shift), прыжок,
поворот на месте; стопы не проваливаются, шарниры таза видны при шаге.
