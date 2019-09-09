FROM abaez/luarocks

RUN apk update && apk add cmake g++ 
RUN luarocks install luv dromozoa-shlex

ADD *.lua /app/
ADD test.sh /app/
WORKDIR /app
EXPOSE 8080

CMD ["lua", "caas.lua"]
