FROM abaez/luarocks

COPY . /app
WORKDIR /app

RUN apk update && apk add cmake g++ 
RUN luarocks make $(ls *.rockspec)

EXPOSE 8080

ENV CAAS_JOBS_DIR=/caas

CMD caas
