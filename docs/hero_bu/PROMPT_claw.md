Новый этап «Герой Born Unblessed + экраны запуска и загрузки + уборка мира».
Работаем в ветке born-unblessed. Начинай после этапа меню Born Unblessed
(комплект использует его тему и кнопки). Если этап меча ещё не сделан — он входит в этот.

0. Номер этапа: следующий свободный после последнего в docs/SPEC.md; дальше везде
   подставляй его вместо «П5.N».

1. Распакуй комплект, ничего не перезаписывая:
   cd ~/blockparty && git checkout born-unblessed && git pull
   unzip -n ~/born_unblessed_hero_kit_final.zip -d ~/blockparty
   Если unzip сообщит, что какой-то файл уже существует, — остановись и позови меня.
   Модель assets/hero_bu/knight_bu.glb (13 МБ) — через Git LFS, как остальные .glb.

2. С моего согласия добавь в конец docs/SPEC.md содержимое docs/hero_bu/SPEC_hero_bu.md,
   заменив «П5.N» на номер этапа, отдельным коммитом «SPEC: этап П5.N (герой Born Unblessed)».

2а. С моего согласия допиши в конец docs/CONCEPT_born_unblessed.md содержимое
   docs/hero_bu/LORE_bu.md (мир игры утверждён), отдельным коммитом «CONCEPT: мир Born Unblessed».

3. Запусти Claude Code в ~/blockparty с задачей:
   «Прочитай CLAUDE.md, docs/SPEC.md (раздел П5.N), docs/hero_bu/README.md
   и docs/sword_bu/README.md. Выполни этап П5.N:
   — герой игрока (свой и чужие) — assets/hero_bu/hero_bu.tscn, редактор внешности скрыть;
   — анимации пака Mixamo Sword and Shield из assets_src/mixamo_sword перенести на героя
     инструментом tools/retarget_mixamo_bu.gd, локомоцию собрать из клипов пака,
     меч — EquipControllerBU по этапу меча;
   — жителей, костёр и задания жителей выключить одним флагом, код не удалять;
   — экран запуска показать через BootScreenBU (scenes/boot_bu), логику Steam не менять;
   — вход в мир (новая игра, продолжить, глава, подключение, офлайн) — через
     LoadingScreenBU (scenes/loading_bu), у корня мира сигнал world_ready;
   — подключить i18n/strings_bu_boot.csv.
   Код комплекта не переписывай без необходимости, все правки — в docs/STATUS.md.
   Скриншоты tools/capture_hero_bu.gd и серию из игры — в docs/screenshots/П5.N/
   через xvfb-run -a.»

4. Приёмка как обычно: GUT зелёные (включая tests/test_hero_bu.gd, через xvfb-run -a),
   STATUS.md обновлён, коммит и push в born-unblessed, сборка для Windows.
   В main не сливай — жду ручной проверки по сборке.

5. Позови меня, если: Claude Code хочет переделать героя, перекрасить его или собрать
   из других частей; удалить код жителей/костра вместо флага; пак Sword and Shield
   не найден; инструмент переноса пишет static больше 1; нужно что-то скачать;
   без жителей ломается что-то кроме заданий.
