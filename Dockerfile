# Образ с самим инструментом: та же сборка, что и локально, только запакованная.
# Гемы у нас чистые ruby (rack, thor, webrick), нативных расширений нет —
# поэтому хватает alpine без пакетов для компиляции.
FROM ruby:3.3-alpine

# Установка гемов кешируется отдельным слоем: без правок Gemfile образ
# пересобирается за секунды.
WORKDIR /app
COPY Gemfile Gemfile.lock ./
# В образ едут только гемы самого инструмента: тесты и линтер там не запускаются.
RUN bundle config set --local without "development test" \
 && bundle install --jobs 4 --retry 2 \
 && rm -rf /usr/local/bundle/cache

COPY app ./app
COPY bin ./bin
COPY docs ./docs
COPY examples ./examples
COPY config.ru ./

# В контейнере слушаем все адреса: иначе проброшенный порт не отвечает.
# Профиль контракта переключается той же переменной, что и локально.
ENV RSOCKET_HOST=0.0.0.0 \
    RSOCKET_PORT=9292 \
    RSOCKET_CONTRACT=space_payments \
    RSOCKET_STORAGE=local

# Сборка ничего не пишет за пределы output/, поэтому root не нужен.
RUN adduser -D -H rsocket && mkdir -p /app/output && chown rsocket /app/output
USER rsocket

EXPOSE 9292

# По умолчанию поднимается сервер. Хранилище задаётся снаружи: RSOCKET_STORAGE=s3
# плюс настройки бакета — тогда правила и результат живут в нём. Разовая сборка
# идёт тем же образом и остаётся локальной:
#   docker run --rm -v "$PWD:/work" rsocket \
#     bundle exec bin/rsocket build -s /work/provider_api.yaml -p novapay -o /work/output
CMD ["bundle", "exec", "bin/rsocket", "serve"]
