FROM abaez/luarocks

RUN apk update && apk add cmake g++ 
RUN luarocks install luv && luarocks install dromozoa-shlex

ADD *.lua /app/
WORKDIR /app
EXPOSE 8080

CMD ["lua", "caas.lua"]
