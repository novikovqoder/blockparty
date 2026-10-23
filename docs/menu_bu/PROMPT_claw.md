Новый этап П5.9 «Главное меню Born Unblessed».

1. Распакуй комплект в проект, ничего не перезаписывая вне новых папок:
   cd ~/blockparty && git checkout main && git pull && git checkout -b p5.9-menu-bu
   unzip -n ~/born_unblessed_menu_kit.zip -d ~/blockparty
   Если unzip сообщит, что какой-то файл уже существует, — остановись и позови меня.
2. С моего согласия добавь в конец docs/SPEC.md содержимое файла
   docs/menu_bu/SPEC_P5.9.md (без изменений) и закоммить это отдельным коммитом
   «SPEC: этап П5.9 (меню Born Unblessed)».
3. Запусти Claude Code в ~/blockparty с задачей:
   «Прочитай CLAUDE.md, docs/SPEC.md (раздел П5.9) и docs/menu_bu/README.md.
   Выполни этап П5.9: встрой готовый комплект меню из scenes/menu_bu, ui/theme_bu,
   assets/menu_bu, i18n/strings_bu.csv. Код комплекта не переписывай без
   необходимости, все правки перечисли в docs/STATUS.md. Сними скриншоты
   tools/capture_menu_bu.gd в docs/screenshots/P5.9/ через xvfb-run -a.»
4. Приёмка как обычно: тесты GUT зелёные (включая tests/test_main_menu_bu.gd),
   STATUS.md обновлён, коммит и push, сборка для Windows.
   В main НЕ сливай: этап ждёт моей ручной проверки по сборке.
5. Позови меня, если Claude Code захочет переделать меню с нуля, удалить
   старое меню без dev-аргумента --old-menu или что-то скачать.
