FROM kaspergrubbe/grubruby-jemalloc:3.2.2.9023
  RUN apt-get -yq update && apt-get -yqq install fping

  WORKDIR /usr/src/app

  # To mitigate an issue in Buildkit here: https://github.com/moby/moby/issues/38964
  COPY Gemfile ./
  COPY Gemfile.lock ./

  RUN mkdir -p /usr/local/etc \
    && { \
      echo 'install: --no-document'; \
      echo 'update: --no-document'; \
    } >> /usr/local/etc/gemrc

  # throw errors if Gemfile has been modified since Gemfile.lock
  RUN bundle config --global frozen 1

  RUN bundle install --jobs 16

  COPY infping.rb ./

  # Create a non-root user and a group
  ENV USER_GROUP=infpingrb
  RUN groupadd -r ${USER_GROUP} && \
      useradd --home-dir /home/${USER_GROUP} --create-home -g ${USER_GROUP} ${USER_GROUP}
  RUN chown -R ${USER_GROUP}:${USER_GROUP} /usr/src/app/*

  # From here onwards, any RUN, CMD, or ENTRYPOINT will be run under the following user instead of 'root'
  USER ${USER_GROUP}

  ENV LD_PRELOAD=/usr/local/lib/libjemalloc5.so

  CMD ["bundle", "exec", "ruby", "infping.rb"]
