.PHONY: run build gen docs tidy clean

# 本地运行
run:
	go run ./cmd

# 编译到 bin/
build:
	go build -trimpath -ldflags="-s -w" -o bin/QLToolsV2 ./cmd

# 改动 internal/data/ent/schema/*.go 之后必须执行，重新生成 Ent 代码
# 等价于：cd internal/data/ent && go generate ./...
gen:
	cd internal/data/ent && go generate ./...

# 重新生成 Swagger 文档（需要先安装 swag）
docs:
	swag init -g cmd/main.go -o docs

# 整理依赖
tidy:
	go mod tidy

clean:
	rm -rf bin
