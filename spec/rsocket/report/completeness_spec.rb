# frozen_string_literal: true

require "spec_helper"
require "tempfile"

# T4.2: всё, чего мы не поняли, обязано доехать до отчёта.
#
# Проверяется на нарочно урезанном описании — без примеров, без описанных
# ошибок, без объявленной авторизации, с незнакомым статусом и без единиц
# суммы. Это тот случай, когда инструмент проще всего заставить молчать, а
# молчание здесь опаснее любой ошибки: человек считает, что всё разобрано.
#
# Проверка сквозная — от чтения файла до печати отчёта, — поэтому названа
# свойством, а не классом.
# rubocop:disable-next RSpec/DescribeClass
RSpec.describe "полнота отчёта" do
  let(:trimmed) do
    <<~YAML
      openapi: 3.0.3
      info:
        title: Урезанное описание
        version: 0.1.0
      paths:
        /things:
          post:
            operationId: createThing
            requestBody:
              required: true
              content:
                application/json:
                  schema:
                    type: object
                    properties:
                      amount: { type: integer }
                      currency: { type: string }
                      recipient:
                        type: object
                        properties:
                          phone: { type: string }
            responses:
              '201':
                description: создано
                content:
                  application/json:
                    schema:
                      type: object
                      properties:
                        id: { type: string }
                        status: { type: string, enum: [quantum_flux] }
    YAML
  end

  let(:sections) { report.sections }
  let(:asks) { sections.needs_confirmation.map(&:title) }

  def report
    file = Tempfile.new(["trimmed", ".yaml"])
    file.write(trimmed)
    file.close
    spec = Rsocket::Spec::Normalizer.normalize(Rsocket::Spec::Loader.load(file.path))
    Rsocket::Report::Report.new(spec, Rsocket::Classify::Classifier.call(spec))
  end

  it "сообщает, что примеров запросов и ответов нет" do
    expect(asks).to include(a_string_matching(/не описано ни одного примера/))
  end

  it "сообщает, что ошибки не описаны" do
    expect(asks).to include(a_string_matching(/не описаны ответы с ошибками/))
  end

  it "сообщает, что авторизация не объявлена" do
    expect(asks).to include(a_string_matching(/нет ни одной схемы авторизации/))
  end

  it "сообщает про статус, которого нет в словаре" do
    expect(asks).to include(a_string_matching(/без перевода: quantum_flux/))
  end

  it "показывает непереведённый статус прямо в списке статусов" do
    details = sections.needs_confirmation.flat_map(&:details)

    expect(details).to include(a_string_matching(/quantum_flux → не определено/))
  end

  # Одного слабого признака мало: «поле целочисленное» не доказывает копейки, а
  # ошибка в единицах суммы стоит дороже любой другой.
  it "не выдумывает единицы суммы по одному слабому признаку" do
    expect(asks).to include(a_string_matching(/Единицы суммы не определены/))
  end

  it "называет роли, которые не нашлись" do
    expect(asks).to include(a_string_matching(/«приём уведомлений» не определена/))
  end

  # Роль всё же найдена по форме запроса, но признаков хватило только на
  # «проверьте»: описание бедное, и уверенности взяться неоткуда.
  it "находит роль по форме запроса, но не выдаёт её за уверенный вывод" do
    expect(asks).to include(a_string_matching(%r{создание выплаты → POST /things}))
  end
end
