
# docker方式安装ElasticSearch



### 前言：

项目中要用到 ElasticSearch，以前都是使用单机版，既然是正式使用，就需要学习一下集群啥的，也要把安全性考虑进去。

刚入手的MacBook Pro M2 16寸（ M2 ARM64） ，其实对容器以及虚拟机的兼容性还是有点不确定，所以这次会同时在旧的 MacBook Pro 2015 15寸（ Intel I7） 同时安装测试。

参考：搜了一下，往上大多都是同样的方式安装，我基本参考 简书上“[卖菇凉的小火柴丶](https://www.jianshu.com/u/61b931008444)”的文章 [docker-compose安装elasticsearch8.5.0集群](https://www.jianshu.com/p/9ae39a8beeef ) 

### 先测试单机版

准备好环境文件 .env ，这个env文件会在后面几个测试方案中一直使用。

```properties
# elastic账号的密码 (至少六个字符),别用纯数字，否则死给你看
ELASTIC_PASSWORD=iampassword

# kibana_system账号的密码 (至少六个字符)，该账号仅用于一些kibana的内部设置，不能用来查询es，,别用纯数字，否则死给你看
KIBANA_PASSWORD=iampassword

# es和kibana的版本
STACK_VERSION=7.17.9

# 集群名字
CLUSTER_NAME=docker-cluster

# x-pack安全设置，这里选择basic，基础设置，如果选择了trail，则会在30天后到期
LICENSE=basic
#LICENSE=trial

# es映射到宿主机的的端口
ES_PORT=9200

# kibana映射到宿主机的的端口
KIBANA_PORT=5601

# es容器的内存大小，请根据自己硬件情况调整(字节为单位，当前1G)
MEM_LIMIT=1073741824

# 命名空间，会体现在容器名的前缀上
COMPOSE_PROJECT_NAME=es
```

然后准备 docker-compose.yaml 

```yaml
version: '3'
services:
  es-single:
    image: elasticsearch:${STACK_VERSION}
    container_name: es-single
    volumes:
      - ./data/esdata01:/usr/share/elasticsearch/data
    ports:
      - 9200:9200
      - 9300:9300
    environment:
      - node.name=es-single
      - cluster.name=es-docker-cluster
      - discovery.type=single-node
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - bootstrap.memory_lock=true
      - xpack.security.enabled=true
    mem_limit: ${MEM_LIMIT}
    ulimits:
      memlock:
        soft: -1
        hard: -1
        
  kibana-single:
    depends_on:
      - es-single
    image: kibana:${STACK_VERSION}
    container_name: kibana-single
    ports:
        - ${KIBANA_PORT}:5601
    volumes:
      - ./data/kibanadata:/usr/share/kibana/data

    environment:
      - SERVERNAME=kibana-single
      - ELASTICSEARCH_HOSTS=http://es-single:9200
      - ELASTICSEARCH_USERNAME=elastic
      - ELASTICSEARCH_PASSWORD=${KIBANA_PASSWORD}
    mem_limit: ${MEM_LIMIT}
```

然后启动 `docker-compose up -d` 

稍等十几秒后在查看 `curl -u elastic:iampassword http://localhost:9200` *（浏览器里也可以直接查看，不过这样显得牛逼）*

```json
{
  "name" : "es-single",
  "cluster_name" : "es-docker-cluster",
  "cluster_uuid" : "0pIB-A9kScyLkhj6YkYSjA",
  "version" : {
    "number" : "7.17.9",
    "build_flavor" : "default",
    "build_type" : "docker",
    "build_hash" : "ef48222227ee6b9e70e502f0f0daa52435ee634d",
    "build_date" : "2023-01-31T05:34:43.305517834Z",
    "build_snapshot" : false,
    "lucene_version" : "8.11.1",
    "minimum_wire_compatibility_version" : "6.8.0",
    "minimum_index_compatibility_version" : "6.0.0-beta1"
  },
  "tagline" : "You Know, for Search"
}
```

再过十几秒后网页打开 http://localhost:5601  看就可以看到登录页面。

装逼的样子就是这样

```bash
$ curl -v  http://localhost:5601
*   Trying 127.0.0.1:5601...
* Connected to localhost (127.0.0.1) port 5601 (#0)
> GET / HTTP/1.1
> Host: localhost:5601
> User-Agent: curl/7.86.0
> Accept: */*
>
* Mark bundle as not supporting multiuse
< HTTP/1.1 302 Found
< location: /login?next=%2F
< x-content-type-options: nosniff
< referrer-policy: no-referrer-when-downgrade
< content-security-policy: script-src 'unsafe-eval' 'self'; worker-src blob: 'self'; style-src 'unsafe-inline' 'self'
< kbn-name: f382d92d1bda
< kbn-license-sig: da420c53321c02b93e5b67b614ccdf37075cab5cc99a13d97fca5727603889d0
< cache-control: private, no-cache, no-store, must-revalidate
< content-length: 0
< Date: Sat, 18 Feb 2023 04:54:46 GMT
< Connection: keep-alive
< Keep-Alive: timeout=120
<
```

这样单机本的就好了。



### 集群版

新建一个 cluster 目录，把 .env 文件复制进去 ，

准备一个启动完后的安装脚本 setup-cluster.sh, 主要是设置kibana 登录的密码

```sh

echo "Setting kibana_system password";
until curl -s -X POST -u elastic:${ELASTIC_PASSWORD} -H "Content-Type: application/json" https://es01:9200/_security/user/kibana_system/_password -d "{\"password\":\"${KIBANA_PASSWORD}\"}" | grep -q "^{}"; do sleep 10; done;
echo "All done!";
```

创建新的docker-compose.yaml文件，内容如下：

```yaml
version: '3'
services:
  setup-cluster:
    image: elasticsearch:${STACK_VERSION}
    container_name: setup-cluster
    volumes:
      - ./setup-cluster.sh:/setup-cluster.sh
    environment:
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - KIBANA_PASSWORD=${KIBANA_PASSWORD}
    user: "0"
    command: >
      bash /setup-cluster.sh

  es-cluster-01:
    depends_on: 
      - setup-cluster
    image: elasticsearch:${STACK_VERSION}
    container_name: es-cluster-01
    volumes:
      - ./data/esdata01:/usr/share/elasticsearch/data
    ports:
      - 9200:9200
      - 9300:9300
    environment:
      - node.name=es-cluster-01
      - cluster.name=${CLUSTER_NAME}
      - cluster.initial_master_nodes=es-cluster-01,es-cluster-02,es-cluster-03
      - discovery.seed_hosts=es-cluster-02,es-cluster-03
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - bootstrap.memory_lock=true
      # - xpack.license.self_generated.type=${LICENSE}
    mem_limit: ${MEM_LIMIT}
    ulimits:
      memlock:
        soft: -1
        hard: -1
    healthcheck:
      test: curl -u elastic:${ELASTIC_PASSWORD} -s -f localhost:9200/_cat/health >/dev/null || exit 1
      interval: 30s
      timeout: 10s
      retries: 5

  es-cluster-02:
    image: elasticsearch:${STACK_VERSION}
    container_name: es-cluster-02
    depends_on:
      - es-cluster-01
    volumes:
      # - ./certs:/usr/share/elasticsearch/config/certs
      - ./data/esdata02:/usr/share/elasticsearch/data
    ports:
      - '9202:9200'
      - '9302:9300'
    environment:
      - node.name=es-cluster-02
      - cluster.name=${CLUSTER_NAME}
      - cluster.initial_master_nodes=es-cluster-01,es-cluster-02,es-cluster-03
      - discovery.seed_hosts=es-cluster-01,es-cluster-03
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - bootstrap.memory_lock=true
      # - xpack.license.self_generated.type=${LICENSE}
    mem_limit: ${MEM_LIMIT}
    ulimits:
      memlock:
        soft: -1
        hard: -1
    healthcheck:
      test: curl -u elastic:${ELASTIC_PASSWORD} -s -f localhost:9200/_cat/health >/dev/null || exit 1
      interval: 30s
      timeout: 10s
      retries: 5


  es-cluster-03:
    image: elasticsearch:${STACK_VERSION}
    container_name: es-cluster-03
    depends_on:
      - es-cluster-01
    volumes:  
      - ./data/esdata03:/usr/share/elasticsearch/data
    ports:
      - '9203:9200'
      - '9303:9300'
    environment:
      - node.name=es-cluster-03
      - cluster.name=${CLUSTER_NAME}
      - cluster.initial_master_nodes=es-cluster-01,es-cluster-02,es-cluster-03
      - discovery.seed_hosts=es-cluster-01,es-cluster-02
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - bootstrap.memory_lock=true
      # - xpack.license.self_generated.type=${LICENSE}
    mem_limit: ${MEM_LIMIT}
    ulimits:
      memlock:
        soft: -1
        hard: -1
    healthcheck:
      test: curl -u elastic:${ELASTIC_PASSWORD} -s -f localhost:9200/_cat/health >/dev/null || exit 1
      interval: 30s
      timeout: 10s
      retries: 5


        
  kibana-cluster:
    depends_on:
      es-cluster-01:
        condition: service_healthy
      es-cluster-02:
        condition: service_healthy
      es-cluster-03:
        condition: service_healthy
    image: kibana:${STACK_VERSION}
    container_name: kibana-cluster
    ports:
        - ${KIBANA_PORT}:5601
    volumes:
      - ./data/kibanadata:/usr/share/kibana/data

    environment:
      - SERVERNAME=kibana
      - ELASTICSEARCH_HOSTS=http://es-cluster-01:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=${KIBANA_PASSWORD}
    mem_limit: ${MEM_LIMIT}
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s -I http://localhost:5601 | grep -q 'HTTP/1.1 302 Found'",
        ]
      interval: 10s
      timeout: 10s
      retries: 120


```



启动  `docker-compose up -d` 

一分钟后查看 , kibana正在启动

```bash
$ docker-compose ps -a
NAME                IMAGE                  COMMAND                  SERVICE             CREATED              STATUS                             PORTS
es-cluster-01       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-01       About a minute ago   Up About a minute (healthy)        0.0.0.0:9200->9200/tcp, 0.0.0.0:9300->9300/tcp
es-cluster-02       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-02       About a minute ago   Up About a minute (healthy)        0.0.0.0:9202->9200/tcp, 0.0.0.0:9302->9300/tcp
es-cluster-03       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-03       About a minute ago   Up About a minute (healthy)        0.0.0.0:9203->9200/tcp, 0.0.0.0:9303->9300/tcp
kibana-cluster      kibana:7.17.9          "/bin/tini -- /usr/l…"   kibana-cluster      About a minute ago   Up 11 seconds (health: starting)   0.0.0.0:5601->5601/tcp
setup-cluster       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   setup-cluster       About a minute ago   Up About a minute                  9200/tcp, 9300/tcp
```

再过一会还是不见kibana启动好，却发现es-client-01退出，查看日志没有任何错误提示。

```bash
$ docker-compose ps
NAME                IMAGE                  COMMAND                  SERVICE             CREATED             STATUS                                 PORTS
es-cluster-02       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-02       2 minutes ago       Up 2 minutes (healthy)                 0.0.0.0:9202->9200/tcp, 0.0.0.0:9302->9300/tcp
es-cluster-03       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-03       2 minutes ago       Up 2 minutes (healthy)                 0.0.0.0:9203->9200/tcp, 0.0.0.0:9303->9300/tcp
kibana-cluster      kibana:7.17.9          "/bin/tini -- /usr/l…"   kibana-cluster      2 minutes ago       Up About a minute (health: starting)   0.0.0.0:5601->5601/tcp
setup-cluster       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   setup-cluster       2 minutes ago       Up 2 minutes                           9200/tcp, 9300/tcp
```

然后执行想着执行`docker-compose up -d` 把es-client-01起来，结果是

```bash
$ docker-compose ps
NAME                IMAGE                  COMMAND                  SERVICE             CREATED             STATUS                    PORTS
es-cluster-01       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-01       19 minutes ago      Up 16 minutes (healthy)   0.0.0.0:9200->9200/tcp, 0.0.0.0:9300->9300/tcp
es-cluster-03       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-03       19 minutes ago      Up 19 minutes (healthy)   0.0.0.0:9203->9200/tcp, 0.0.0.0:9303->9300/tcp
kibana-cluster      kibana:7.17.9          "/bin/tini -- /usr/l…"   kibana-cluster      19 minutes ago      Up 18 minutes (healthy)   0.0.0.0:5601->5601/tcp
setup-cluster       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   setup-cluster       19 minutes ago      Up 19 minutes             9200/tcp, 9300/tcp
```

这是后02 node又退出了，而且还是没有任何出错提示。感觉是这个集群只有两个能起来。

这时候直接访问es 和 kibana 都正常。

这时候用 ElasticSearch Head 查看es集群，发现一切正常，集群健康值green。



#### 在老款笔记本执行

在2015款MacBook 上执行，这台电脑启动比较慢，应该是cpu 、内存、硬盘速度都不够快。

第一次完提示03不健康，估计是kibana检查重试的次数到了后自己退出了。

```bash
$ docker-compose up -d
[+] Running 4/5
 ⠿ Container setup-cluster   Started                                                                                                                            0.9s
 ⠿ Container es-cluster-01   Healthy                                                                                                                          156.1s
 ⠿ Container es-cluster-03   Error                                                                                                                            155.6s
 ⠿ Container es-cluster-02   Healthy                                                                                                                          156.5s
 ⠿ Container kibana-cluster  Created                                                                                                                            0.1s
dependency failed to start: container for service "es-cluster-03" is unhealthy

$ docker-compose ps
NAME                IMAGE                  COMMAND                  SERVICE             CREATED             STATUS                                 PORTS
es-cluster-01       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-01       2 minutes ago       Up About a minute (health: starting)   0.0.0.0:9200->9200/tcp, 0.0.0.0:9300->9300/tcp
es-cluster-02       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-02       2 minutes ago       Up About a minute (health: starting)   0.0.0.0:9202->9200/tcp, 0.0.0.0:9302->9300/tcp
es-cluster-03       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-03       2 minutes ago       Up About a minute (health: starting)   0.0.0.0:9203->9200/tcp, 0.0.0.0:9303->9300/tcp
setup-cluster       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   setup-cluster       2 minutes ago       Up About a minute                      9200/tcp, 9300/tcp


```

这时候就手动启动 docker-compose up -d

```bash
$ docker-compose up -d
[+] Running 5/5
 ⠿ Container setup-cluster   Running                                                                                                                            0.0s
 ⠿ Container es-cluster-01   Healthy                                                                                                                            0.6s
 ⠿ Container es-cluster-03   Healthy                                                                                                                            0.6s
 ⠿ Container es-cluster-02   Healthy                                                                                                                            0.6s
 ⠿ Container kibana-cluster  Started
 
```

但是这时候kibana怎么也启动不起来，检查日志发现

es-cluster-02  | {"type": "server", "timestamp": "2023-02-18T06:11:25,259Z", "level": "WARN", "component": "o.e.c.r.a.DiskThresholdMonitor", "cluster.name": "docker-cluster", "node.name": "es-cluster-02", "message": "high disk watermark [90%] exceeded on [pdT2lWRmQEi04k5GYvrWuA][es-cluster-01][/usr/share/elasticsearch/data/nodes/0] free: 88.6gb[9.2%], shards will be relocated away from this node; currently relocating away shards totalling [0] bytes; the node is expected to continue to exceed the high disk watermark when these relocations are complete", "cluster.uuid": "xaadt2vISeWTK4hk8RDJeA", "node.id": "7rYuhhyeS86iyKOtUChBKw"  }



大致意思是我硬盘空间快满了，shards将不会分配给这个node，搜了一下解决办法就是

```
curl -XPUT "http://localhost:9200/_cluster/settings" \
 -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "cluster": {
      "routing": {
        "allocation.disk.threshold_enabled": false
      }
    }
  }
}'
```

执行完以后看到 kibana 日志就迅速滚动起来。后面再看看 kibana 启动时候都干了啥，为啥这么慢。

这时候 cpu 占用比较高，风扇哗啦啦响。

过了好久发现es-cluster-01 退出了，依然是没有任何错误提示，kibana自己提示 unhealthy 了。

```
$ docker-compose ps
NAME                IMAGE                  COMMAND                  SERVICE             CREATED             STATUS                      PORTS
es-cluster-02       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-02       30 minutes ago      Up 29 minutes (healthy)     0.0.0.0:9202->9200/tcp, 0.0.0.0:9302->9300/tcp
es-cluster-03       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   es-cluster-03       30 minutes ago      Up 29 minutes (healthy)     0.0.0.0:9203->9200/tcp, 0.0.0.0:9303->9300/tcp
kibana-cluster      kibana:7.17.9          "/bin/tini -- /usr/l…"   kibana-cluster      29 minutes ago      Up 26 minutes (unhealthy)   0.0.0.0:5601->5601/tcp
setup-cluster       elasticsearch:7.17.9   "/bin/tini -- /usr/l…"   setup-cluster       30 minutes ago      Up 29 minutes               9200/tcp, 9300/tcp
```

唉~看来es集群没问题，但是启动kibana的时候会较多的事情。再次重新启动，这时候一切正常了。

下面研究为啥cluster只启动两个的问题。这时候访问任何一个 node ，感觉都是健康的。

窃以为需要启动偶数个，就把真个集群变成 4 个node，然而已启动第一个node就退出，只有三个在跑，尝试把第一个起来后，第二个 node 又退出了。过了一会 kibana 起来后，第四个 node 也退出了。

这世道乱了，还是去官网看看吧。



