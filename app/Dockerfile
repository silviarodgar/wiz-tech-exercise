# =============================================================================
# Stage 1: Build the Go binary
# =============================================================================
FROM golang:1.19 AS build

WORKDIR /go/src/tasky
COPY . .
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /go/src/tasky/tasky

# =============================================================================
# Stage 2: Final runtime image — intentionally outdated Alpine 3.17.0
# =============================================================================
FROM alpine:3.17.0 as release

WORKDIR /app
COPY --from=build /go/src/tasky/tasky .
COPY --from=build /go/src/tasky/assets ./assets

# Required by Wiz exercise — validate with: kubectl exec <pod> -- cat /app/wizexercise.txt
COPY wizexercise.txt /app/wizexercise.txt

EXPOSE 8080
ENTRYPOINT ["/app/tasky"]
