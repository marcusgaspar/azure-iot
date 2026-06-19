# Fluxo entre o Broker MQTT default (aio-broker) e o Connector MQTT

Explicação didática de como os dados fluem do app de video-analytics até o broker
interno do Azure IoT Operations (AIO), passando pelo Connector MQTT.

## Os dois brokers em jogo

No cluster existem **dois** brokers MQTT diferentes. Não confunda:

| Broker           | Quem é                                 | Porta | Segurança           | Papel                                                 |
| ---------------- | -------------------------------------- | ----- | ------------------- | ----------------------------------------------------- |
| **`demo1883`**   | Listener inseguro que **você** criou   | 1883  | Nenhuma (anonymous) | Broker **externo/de campo** — onde o app publica      |
| **`aio-broker`** | Broker **default do AIO** (vem pronto) | 18883 | TLS + SAT           | Broker **central do AIO** — o "coração" da plataforma |

> Pense no `aio-broker` como o **barramento interno oficial** do Azure IoT Operations.
> Tudo que é "de verdade" no AIO trafega por ele. O `demo1883` é só uma porta de
> entrada simples que você abriu para o app conseguir publicar sem TLS.

## O que o Connector MQTT faz

O **Connector MQTT** é uma **ponte (bridge)**. A função dele é uma só:

> "Eu me conecto a um broker MQTT **de fora**, escuto certos tópicos, e **copio**
> as mensagens para dentro do `aio-broker`."

Ele tem **dois lados**:

```
       LADO ORIGEM                          LADO DESTINO
   (você configurou no Device)        (o connector sempre usa)
   ┌─────────────────────┐            ┌─────────────────────┐
   │   Server URL =      │            │   aio-broker        │
   │   mqtt://demo1883   │  ───────►  │   :18883 (TLS+SAT)  │
   │   :1883             │            │                     │
   └─────────────────────┘            └─────────────────────┘
        ASSINA (subscribe)                PUBLICA (publish)
```

- **Lado ORIGEM** = o que você colocou no **Server URL** (`mqtt://demo1883...:1883`).
  É onde ele **lê** os dados.
- **Lado DESTINO** = o `aio-broker` interno. É onde ele **escreve** os dados.
  **Isso é automático** — você não configura, o connector já sabe que o destino é o
  broker do AIO.

## Onde entram o Device e o Asset

Esses dois recursos só **detalham** os dois lados da ponte:

```
DEVICE  ──► define o LADO ORIGEM (a conexão)
            • Server URL = mqtt://demo1883...:1883
            • Authentication = Anonymous

ASSET   ──► define O QUE copiar e PARA ONDE
   └─ Dataset
        • Data source  = video-analytics/detections   ◄── tópico que ele ASSINA no demo1883
        • Destination Topic = azure-iot-operations/data/camera-01  ◄── tópico onde PUBLICA no aio-broker
```

## O fluxo completo, passo a passo

```
  ┌──────────────┐
  │  main.py     │  1. O app publica o JSON de detecção
  │  (o app)     │     no tópico: video-analytics/detections
  └──────┬───────┘
         │ publish (1883, sem TLS)
         ▼
  ┌──────────────┐
  │  demo1883    │  2. As mensagens ficam aqui (broker de campo)
  │  :1883       │
  └──────┬───────┘
         │ o connector ASSINA "video-analytics/detections"
         │ (porque você pôs isso em Data source)
         ▼
  ┌──────────────┐
  │ CONNECTOR    │  3. A ponte lê cada mensagem...
  │   MQTT       │     ...e republica em "azure-iot-operations/data/camera-01"
  └──────┬───────┘
         │ publish (18883, TLS + SAT) ← automático
         ▼
  ┌──────────────┐
  │  aio-broker  │  4. Agora o dado está dentro do AIO oficial,
  │  :18883      │     pronto para Data Flows, cloud, etc.
  └──────────────┘
```

## Por que o teste no demo1883 falhou

Teste incorreto:

```bash
mosquitto_sub -h demo1883 -p 1883 -t "azure-iot-operations/data/#"
```

Isso é o equivalente a **procurar a carta na caixa de origem depois que o carteiro já
a levou**. O tópico `azure-iot-operations/data/...` só existe no **destino**
(`aio-broker`), nunca no `demo1883`. Por isso não aparece nada.

Para ver o resultado da ponte, é preciso ouvir o **destino**
(`aio-broker:18883` com TLS+SAT) — exatamente o comando que existe nas últimas linhas
de `scripts/Pub-Sub-Tests.sh`:

```bash
mosquitto_sub \
  --host aio-broker \
  --port 18883 \
  --topic "azure-iot-operations/data/#" \
  -v \
  --debug \
  --cafile /var/run/certs/ca.crt \
  -D CONNECT authentication-method 'K8S-SAT' \
  -D CONNECT authentication-data $(cat /var/run/secrets/tokens/broker-sat)
```

> Esse comando precisa rodar **dentro de um pod** que tenha o CA montado em
> `/var/run/certs/ca.crt` e o token SAT em `/var/run/secrets/tokens/broker-sat`.

## Resumo em uma frase

> O **app** joga dados no **`demo1883`**. O **connector** é uma **ponte** que lê do
> `demo1883` (origem que você configurou) e copia para o **`aio-broker`** (destino
> oficial do AIO, automático). O **Device** descreve a origem; o **Asset/Dataset**
> descreve qual tópico copiar e para qual tópico de destino.
