Новый этап «Меч героя». Ставь в очередь: начинай только после того, как этап П5.10
«Персонажи» принят и герой игры выбран (меч крепится к его скелету).

0. Номер этапа: возьми следующий свободный номер после последнего этапа в docs/SPEC.md
   и дальше везде подставляй его вместо «П5.N».

1. Распакуй комплект в проект, ничего не перезаписывая:
   cd ~/blockparty && git checkout main && git pull && git checkout -b sword-bu
   unzip -n ~/born_unblessed_sword_kit.zip -d ~/blockparty
   Если unzip сообщит, что какой-то файл уже существует, — остановись и позови меня.
2. Найди на сервере пак анимаций Mixamo «Pro Sword and Shield Pack»
   (zip или папка с файлами вида «sword and shield idle.fbx», «draw sword 2.fbx»):
   find ~ -iname "*sword*shield*" 2>/dev/null
   Скопируй все его .fbx в ~/blockparty/assets_src/mixamo_sword/ и добавь эту папку
   в .gitignore. Если пак не найден — остановись и позови меня, ничего не скачивай.
3. С моего согласия добавь в конец docs/SPEC.md содержимое файла
   docs/sword_bu/SPEC_sword_bu.md, заменив в заголовке «П5.N» на номер этапа, отдельным коммитом
   «SPEC: этап П5.N (меч героя)».
4. Запусти Claude Code в ~/blockparty с задачей:
   «Прочитай CLAUDE.md, docs/SPEC.md (раздел П5.N) и docs/sword_bu/README.md.
   Выполни этап П5.N: перенеси анимации пака из assets_src/mixamo_sword на текущего
   героя инструментом tools/retarget_mixamo_bu.gd в assets/hero/hero_sword_anims.res,
   подключи библиотеку под именем sword и добавь герою EquipControllerBU с мечом
   assets/sword_bu/sword_bu.glb (выхватывание sword/draw_sword_2, убирание
   sword/sheath_sword_1, стойка с мечом sword/ss_idle). Код комплекта не переписывай
   без необходимости, все правки перечисли в docs/STATUS.md. Сними скриншоты
   tools/capture_sword_bu.gd в docs/screenshots/П5.N/ через xvfb-run -a.»
5. Приёмка как обычно: тесты GUT зелёные (включая tests/test_sword_bu.gd),
   STATUS.md обновлён, коммит и push, сборка для Windows.
   В main НЕ сливай: этап ждёт моей ручной проверки по сборке.
6. Позови меня, если: скелет героя не Mixamo; Claude Code захочет переписать
   комплект или переделать героя; инструмент переноса пишет static больше 1;
   нужно что-то скачать.
