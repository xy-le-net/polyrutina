FROM dart:stable AS build
WORKDIR /app
COPY build/web /app
RUN dart pub global activate dhttpd
ENV PATH="$PATH:$HOME/.pub-cache/bin"
EXPOSE 8080
CMD ["dhttpd", "--host", "0.0.0.0", "--port", "8080"]