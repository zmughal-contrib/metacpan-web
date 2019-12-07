FROM metacpan/metacpan-base:latest

ARG CPM_ARGS=--without-test

RUN apt install -f && curl -sL https://deb.nodesource.com/setup_10.x | bash \
    && curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y nodejs yarn

ENV PERL_MM_USE_DEFAULT=1

COPY . /metacpan-web/
WORKDIR /metacpan-web

RUN yarn install

RUN cpanm --notest App::cpm \
    && cpm install -g Carton \
    && useradd -m metacpan-web -g users \
    && cpm install -g ${CPM_ARGS}\
    && rm -fr /root/.cpanm /root/.perl-cpm /tmp/*

RUN chown -R metacpan-web:users /metacpan-web

USER metacpan-web:users

EXPOSE 5001

CMD ["plackup", "-p", "5001", "-r"]
