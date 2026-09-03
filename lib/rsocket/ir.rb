# frozen_string_literal: true

# Общий вид описания API, к которому сводится любой прочитанный файл.
#
# Дальше по конвейеру про OpenAPI никто не знает и знать не должен: между
# чтением и генерацией стоит один набор неизменяемых значений. Появится другой
# формат описания — менять придётся только spec/, всё остальное не заметит.

require_relative "ir/note"
require_relative "ir/server"
require_relative "ir/security_scheme"
require_relative "ir/field"
require_relative "ir/response"
require_relative "ir/operation"
require_relative "ir/spec"
