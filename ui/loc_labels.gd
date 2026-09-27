# Утилита локализации для сцен: узлам Label и Button с метаданными tr_key
# присваивается переведённый текст. Все строки UI идут через tr() и
# i18n/strings.csv (правило проекта).
# Не делает: не следит за сменой языка в рантайме (переводы применяются при _ready).
class_name LocLabels


static func apply(root: Node) -> void:
	_apply_recursive(root)


static func _apply_recursive(node: Node) -> void:
	if node.has_meta("tr_key"):
		var key: String = str(node.get_meta("tr_key"))
		# tr() — метод узла, поэтому вызываем его у самого локализуемого узла.
		if node is Label:
			(node as Label).text = (node as Label).tr(key)
		elif node is Button:
			(node as Button).text = (node as Button).tr(key)
	for child: Node in node.get_children():
		_apply_recursive(child)
