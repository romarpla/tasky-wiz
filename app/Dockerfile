# Building the binary of the App
FROM golang:1.19 AS build

WORKDIR /go/src/tasky
COPY . .
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /go/src/tasky/tasky


FROM alpine:3.17.0 as release

WORKDIR /app
COPY --from=build  /go/src/tasky/tasky .
COPY --from=build  /go/src/tasky/assets ./assets

# Database info
ENV MONGODB_URI=mongodb://host.docker.internal:27017
ENV SECRET_KEY="asdasd"

#run locally
EXPOSE 8080

# Wiz exercise requirement: file with the candidate's name baked into the image
COPY wizexercise.txt /app/wizexercise.txt
EXPOSE 8080
ENTRYPOINT ["/app/tasky"]
