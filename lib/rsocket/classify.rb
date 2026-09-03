# frozen_string_literal: true

# Определение смысла: что за что отвечает в описании API.
#
# Загрузчик и нормализатор отвечают на вопрос «что написано в файле», эта часть —
# на вопрос «что это значит»: какая операция создаёт выплату, какие статусы
# означают успех, какие ошибки можно повторять, в чём передаётся сумма. Именно
# здесь разработчик обычно тратит два дня на чтение чужой документации.
#
# Три правила, которым подчинено всё внутри:
#
#   1. Никаких нейросетей. Одинаковый вход обязан давать одинаковый результат.
#   2. Логика в коде, знания в словарях: добавление роли не меняет ни строки Ruby.
#   3. Ниже порога не угадываем. Честное «не определил» дешевле тихой ошибки.

require_relative "classify/evidence"
require_relative "classify/text"
require_relative "classify/result"
require_relative "classify/meanings"
require_relative "classify/roles"
require_relative "classify/scoring"
require_relative "classify/role_matcher"
require_relative "classify/status_mapper"
require_relative "classify/error_mapper"
require_relative "classify/money_detector"
require_relative "classify/webhook_detector"
require_relative "classify/signals/lexicon"
require_relative "classify/signals/signature"
require_relative "classify/signals/lifecycle"
require_relative "classify/classifier"
