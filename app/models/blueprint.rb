# frozen_string_literal: true

module Models
  # Всё, что нужно шаблону, чтобы напечатать класс под контракт заказчика. Ничего
  # вычислять по дороге шаблон не должен — здесь уже готовые значения.
  Blueprint = Struct.new(
    :provider,            # novapay
    :contract,            # имя профиля контракта, под который собрано
    :class_name,          # NovapayService
    :env_prefix,          # NOVAPAY
    :base_url,
    :http,                # таймауты и User-Agent из конфига
    :bindings,            # роль → Models::RoleBinding
    :status_map,          # состояние провайдера → статус контракта
    :event_map,           # событие webhook → статус контракта
    :error_map,           # HTTP-код → { code:, action:, symbol: }
    :constraints,         # [Models::Constraint]
    :amount_multiplier,   # 1 или 100
    :amount_expression,   # чем контракт приводит сумму к виду провайдера
    :calls,               # роль → CallPlanner::Request для ролей, ходящих к провайдеру
    :status_field,        # где в ответе лежит статус
    :created_id_field,    # где в ответе лежит идентификатор операции провайдера
    :callback,            # поля тела webhook и подпись
    :credentials,         # авторизация: схемы и готовые строки контракта
    :fixtures,            # примеры запросов, ответов и уведомлений
    :warnings,            # что не удалось сопоставить
    keyword_init: true
  )
end
