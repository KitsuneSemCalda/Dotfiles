# Homologação local: rodada de 2026-10-24

Artefatos recebidos do host: `.qualification/20261025T004416.106875Z/`.
O diretório é ignorado pelo Git e inclui logs, inventário, hashes de fontes/binário
e o resultado de cada etapa. Esta rodada não homologa as dez fases.

O registro abaixo segue a ordem dos testes e correções. Os resultados mais
recentes incluem o protocolo Qwen3-0.6B no LM Studio, controles systemd e
integração Docker em CPU. O ComfyUI passou no smoke de API sem modelo de IA;
geração de imagem/vídeo permanece pendente. Consulte a
[tabela de validação atual](validation.md#estado-por-fase) para o resumo por fase.

## Evidência recebida

- Fase 1 aprovada no escopo medido: contadores de CPU/RAM comparados ao kernel.
- systemd de usuário acessível (`SystemState=degraded`); a criação de um serviço
  transitório ocorreu. O teste falhou na leitura de `io.weight`, ausente no cgroup.
  Isso não comprova que todos os outros controles estão corretos: a verificação
  terminou antes deles.
- Docker: `permission denied` ao acessar `/var/run/docker.sock`. O daemon não foi
  homologado; ausência de acesso não demonstra que ele esteja parado.
- APIs LM Studio e ComfyUI recusaram conexão nas portas padrão.
- Dois GGUFs visíveis em `~/.lmstudio/models/`: GLM-4.7-Flash Q4_K_M
  (18.132.721.120 bytes) e Wan 14B (9.659.931.264 bytes).
- RAM física: 16.465.260.544 bytes; RAM disponível no snapshot:
  7.898.882.048 bytes; swap ocupada: 9.370.116.096 bytes. Ocupação não prova
  atividade de swap naquele instante. Tamanho do GGUF não é uma medição do
  working set, especialmente com mmap e MoE.

## Correção aplicada após a rodada

O verificador supunha que `io.weight` existiria sempre que o serviço aceitasse
`IOWeight=100`. Essa suposição causou a falha observada. O valor padrão neutro é
100, conforme a [documentação do systemd](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html#IOWeight=weight).

Agora, somente a ausência desse arquivo, com peso neutro e sem exigência estrita,
permite continuar. O resultado registra `capability.io_weight` como indisponível;
não inventa um peso aplicado. Permissão negada, valor incorreto em arquivo existente,
peso diferente de 100 e `require_io_weight=true` continuam causando recusa.
Os controles de CPU/memória e nice continuam obrigatórios e verificados.

Testes de regressão cobrem falta de arquivo, pesos não neutros, exigência estrita
e divergência de valor. Sua passagem no sandbox não homologa a integração real.

## Reteste do governor: aprovado no host em 2026-10-25

Na raiz do repositório, fora do sandbox:

```bash
cd inferctl
INFERCTL_REAL_SYSTEMD=1 go test -count=1 -v ./internal/governor -run '^TestSystemdIntegration$'
```

O teste cria um serviço transitório com `sleep`, verifica CPU/memória/nice e
contadores, muda CPUWeight e valida o reset. Não provoca OOM nem executa os modelos.
Somente um novo PASS nesse host permite avançar a fase 4 no escopo desses controles;
a priorização de I/O continuará explicitamente não homologada quando indisponível.

A política padrão recusa o benchmark de IA no estado de swap registrado. Não foi
alterada para fazer o teste passar. A próxima calibração precisa observar atividade
de swap/pressão, confirmar o modelo pela API e definir o orçamento do workload.

## Resultado do reteste informado pelo usuário

Comando executado pelo usuário na sessão real em 2026-10-25; saída recebida no
chat (não executado pelo agente no sandbox):

```text
verified kernel controllers:
  capability.io_weight: unavailable; neutral default only; I/O weighting not verified
  cpu.max: max 100000
  cpu.weight: 80
  memory.high: 67108864
  memory.max: 100663296
  memory.swap.max: 0
  process.nice: 2
--- PASS: TestSystemdIntegration (0.10s)
```

A fase 4 está homologada para criação transitória, CPUWeight, ausência de quota,
MemoryHigh/MemoryMax/MemorySwapMax, nice, leitura de contadores, alteração de peso
e reset no host testado. O teste completo passou, incluindo as verificações após
esse log inicial. Prioridade de I/O permanece indisponível e não homologada.
Não é evidência de desempenho de inferência, pressão severa ou prevenção de OOM.

Próximo gate: fase 2, com inventário da API LM Studio, orçamento de memória e
atividade de swap atual. Depois, comparação/perfis e seleção Pareto com dados
reais (fases 3 e 7). As fases 5, 6, 8, 9 e 10 continuam pendentes.

## Inventário e vmstat recebidos em 2026-10-25

A API real identificou `zai-org/glm-4.7-flash`, Q4_K_M, 30B,
18.132.739.079 bytes, sem instâncias carregadas. O modelo suporta reasoning
`off`/`on`, com padrão `on`. O contexto de treinamento divulgado não é um
motivo para reservar 202752 tokens no benchmark.

O `free -b` recebido registrou 6.936.170.496 bytes de RAM disponível e
8.839.032.832 bytes de swap ocupada. Nas quatro amostras de um segundo do
`vmstat` após a linha cumulativa, `so=0`; `si` foi 0, 0, 396, 0 KiB/s. Isso
é evidência de um pico isolado de swap-in nesse intervalo, não evidência de
estabilidade sob inferência ou ausência de pressão durante carga de modelo.

Próxima observação necessária: estimativa de carga com contexto de 4096 pelo
`lms load --estimate-only`, sem carregar o modelo. Conforme a
[documentação de lms load](https://lmstudio.ai/docs/cli/local-models/load), a
estimativa respeita contexto e opções de offload. É uma estimativa do backend,
não uma medição do working set nem um benchmark. O limite absoluto de swap do
perfil permanece inalterado; nenhum teste de inferência foi executado nesta etapa.


## Estimativa de GLM recebida em 2026-10-25

`lms load --estimate-only zai-org/glm-4.7-flash --context-length 4096` retornou
17,51 GiB tanto para GPU quanto para total e informou que os guardrails do backend
permitiriam a carga. A estimativa excede a RAM física de aproximadamente 15,33 GiB,
sem incluir reserva de desktop. Não é um pico medido; não demonstra inviabilidade
universal de mmap/MoE/offload, nem prova estabilidade na sessão atual. Não foi
executada inferência do GLM nesta etapa.

Foi preparado `examples/lmstudio-control.json` para uma bancada menor. A variante
oficial Qwen3-0.6B Q8_0 possui arquivo de 639 MB no
[repositório Qwen](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/tree/main), consultado
em 2026-10-25; esse tamanho não é uma estimativa de working set. A chave da API e
a estimativa local precisam ser confirmadas após o download no host.

O perfil usa `swap_accounting=additional`: preserva a swap histórica como métrica
e limita crescimento e tráfego novo de swap, incluindo leitura e escrita, desde
antes da preparação do backend. O limite de 256 MiB não foi aumentado. O modo
original `total` permanece padrão; relatórios antigos sem contadores adicionais
não são aceitos no novo modo. Regressão/overflow de contadores invalida a evidência.
Esses são guardrails configuráveis, não valores alegadamente ótimos nem prova de
responsividade. A bancada pequena não substitui a calibração do GLM.


## Controle instalado: inventário recebido em 2026-10-25

A variante efetivamente instalada tem chave `qwen3-0.6b`, publisher
`lmstudio-community`, Q8_0 e `size_bytes=804753568` na API. O perfil foi atualizado
para essa chave e essa identificação de variante, sem inventar repositório de
origem ou hash de arquivo. O tamanho anunciado pelo repositório oficial usado na
proposta anterior não descreve necessariamente esta variante comunitária.

Há uma instância `qwen3-0.6b` carregada fora do calibrador, com contexto 8192,
eval batch 2048, physical batch 512 e parallel 4. Essa instância não será adotada
como baseline 4k/batch256: precisa ser descarregada explicitamente pelo usuário.
O calibrador então fará sua própria carga, verificará os parâmetros retornados
pela API, executará os candidatos e descarregará as instâncias que criou.

Ainda não há TPS, TTFT ou comparação de inferência recebidos. O próximo ensaio
usa 120 segundos medidos por candidato, warm-up e baseline final, com perfil
`examples/lmstudio-control.json`. O relatório será salvo no workspace em
`.qualification/lmstudio-control/report.json` para análise pelo agente. Falhas de
admissão, swap adicional, temperatura ou API permanecem falhas; não serão
contornadas pela redução posterior dos critérios.


## Primeira tentativa de calibração do controle: admissão recusada

Artefato real recebido em
`.qualification/lmstudio-control/state/benchmarks/cc334c0f9c300295b72b25f6/lmstudio/8a42d1a1a7bacef0/146d0089e0828301/interactive/20261025T033629.229541900Z.json`.
A validação está `incomplete`; não há runs ou preparação do backend e o arquivo
de eventos está vazio. O erro é:

```text
queued: need 2147483648 RAM bytes plus 3293052108 reserve; 5282164736 available
```

Orçamento + reserva exigiam 5.440.535.756 bytes. Faltavam 158.371.020 bytes
(aproximadamente 151 MiB). O zero de TPS do registro não é desempenho observado:
nenhum request de geração foi executado. As fases 2, 3 e 7 continuam pendentes.

Foi corrigida a emissão de stdout: o arquivo externo report.json estava vazio
apesar de existir um relatório interno da recusa. Agora falhas após a criação do
relatório também geram JSON em stdout com erro explícito, preservando exit code
não zero. O teste cobre a recusa de RAM antes de qualquer contato com o backend.

Foi acrescentada a opção `--wait-admission 2m`: espera limitada por candidato e
por aquisição da trava, repetindo as mesmas restrições. Testes cobrem recuperação,
deadline, cancelamento, recusa imediata e ausência de eventos repetitivos. Essa
mudança não reduz a reserva de 20% ou o orçamento de 2 GiB do controle.


## Segunda tentativa do controle: inferência real, protocolo interrompido

Artefato interno: `.qualification/lmstudio-control/state/benchmarks/cc334c0f9c300295b72b25f6/lmstudio/8a42d1a1a7bacef0/146d0089e0828301/interactive/20261025T034142.093222583Z.json`.
O arquivo externo report.json recebido permaneceu vazio/antigo. Não foi inferida a
causa dessa divergência; a evidência abaixo vem do arquivo interno completo.

- Carga confirmada pela API: contexto 4096, eval batch 256; parallel 4,
  physical batch 512, Flash Attention e KV offload permanecem nos valores do
  backend retornados no echo. Nenhuma aplicação de limite systemd a esse servidor
  externo é alegada.
- 13 gerações completas; soma dos tempos dos requests medidos: 117,424 s.
- Mediana: 28,356 TPS; intervalo bootstrap 95%: [28,242; 28,774] TPS.
- TTFT p95 do cliente: 0,143508 s. Temperatura máxima: 76 °C; jitter p95: 1,054 ms.
- Contador de throttling observado não aumentou. Razão entre metades do throughput:
  1,0185. Isso não homologa equilíbrio térmico ou latência real do desktop.
- Swap adicional no pico: 126,980 MiB; tráfego lógico acumulado: 259,582 MiB,
  excedendo o limite configurado de 256 MiB. O monitor cancelou o request e a
  instância foi descarregada, com término do candidato registrado em evento.
- Tráfego de bloco em zram0: 106,219 MiB de leitura e 151,902 MiB de escrita.
  Isso não deve ser apresentado como tráfego ao SSD. Os contadores de bloco não
  permitem atribuir todas as leituras/escritas NVMe ao swapfile.

Não houve candidato batch128 nem baseline final. As fases 2, 3 e 7 continuam
pendentes; não há ganho de performance medido ou perfil recomendado.

Foi acrescentada observabilidade de dispositivos de swap, ZRAM mm_stat e
zswap_enabled no profiler. `host_zram_physical_memory_peak_bytes` registra o uso
físico por dispositivo durante novos benchmarks. O erro/evento de limite agora
inclui modo, ocupação, crescimento, tráfego e limiar, sem alterar o critério.
A documentação primária do [kernel sobre ZRAM](https://docs.kernel.org/admin-guide/blockdev/zram.html)
distingue tamanho lógico, dados comprimidos e memória física do alocador. Consulta
em 2026-10-25, seção Stats/mm_stat. ZRAM também pode ter writeback: sua existência
sozinha não demonstra ausência de tráfego de armazenamento.

### Observação ambiente complementar

O agente executou `tools/observe_pressure.py --duration 120` no ambiente visível
ao sandbox, sem enviar requests de inferência. Artefato:
`.qualification/lmstudio-control/ambient-sandbox.json`.
Foram medidos 23.097.344 bytes (22,027 MiB) de tráfego de swap, crescimento máximo
de 6.955.008 bytes e 0,1100% de tempo total em memory.full/PSI no período.
O uso físico de zram0 ficou acessível via mm_stat; backing_dev informou none e
zswap estava desabilitado. O swapfile separado continuava presente.

Houve testes/builds do agente durante parte dessa coleta; ela não é um ensaio
de máquina ociosa. A observação não é simultânea ao benchmark e não comprova
causalidade nem ausência de outras cargas no host. Nenhum valor foi subtraído do ensaio anterior e o limite
de 256 MiB não foi aumentado. Próximo controle: observar o host na sessão real,
sem novas gerações, usando o mesmo coletor e duração antes de redesenhar o ensaio.


## Controle ambiente no host recebido em 2026-10-25

Artefato: `.qualification/lmstudio-control/ambient-host.json`, duração 120,001 s.
Swap-in: 11.853.824 bytes (11,305 MiB); swap-out: zero; crescimento de swap: zero.
Memory.full correspondeu a 0,3111% do intervalo. RAM disponível mínima:
4.040.978.432 bytes. Esses valores não foram subtraídos do benchmark anterior.
O controle não é simultâneo e não permite atribuir toda a diferença à inferência.

A instância do benchmark retornou parallel=4 para uma carga sequencial. Reduzir
concorrência máxima é uma hipótese de configuração, não uma economia demonstrada:
layout de KV e defaults do runtime podem alterar sua relação com uso de memória.
O [código oficial de lms load](https://github.com/lmstudio-ai/lms/blob/main/src/subcommands/load.ts),
consultado em 2026-10-25, declara `--parallel` e o converte em maxParallelPredictions.
A página REST consultada não documenta esse campo de requisição. Um relato no
bug tracker do fabricante contém `parallel` em um payload, mas não basta para
estabelecer suporte da versão local ou ganho de memória.

Foi preparado `examples/lmstudio-parallel1.json`, separado do protocolo anterior,
com a mesma carga, limites e candidatos de batch, solicitando parallel=1. O adapter
permite esse parâmetro experimental, exige inteiro positivo e verifica exatamente
se o echo_load_config retornou o valor solicitado. API que rejeite ou ignore o
parâmetro causa falha; não há fallback silencioso para parallel=4. A instância
criada permanece identificada para cleanup mesmo se o echo divergir. Testes de
regressão cobrem repasse, divergência e valores inválidos.

Próxima observação: comparar estimativas `lms load --estimate-only` com parallel=1
e parallel=4, mantendo contexto 4096. As estimativas são evidência do estimador,
não do working set. Nenhum novo benchmark de inferência foi executado nesta etapa.


## Estimativas de parallel recebidas e próximo ensaio

O usuário executou no host as estimativas de qwen3-0.6b, contexto 4096, com
parallel=1 e parallel=4. Ambas retornaram 962,09 MiB de GPU e total. A hipótese de
redução de memória por concorrência máxima não recebeu suporte do estimador. Isso
não prova igualdade do working set real, mas não justifica priorizar essa alteração
como economia demonstrada. O perfil experimental parallel1 foi preservado e não
foi executado nem recomendado.

Foi preparado `examples/lmstudio-context.json`: contexto 2048 como baseline,
contexto 4096 como candidato, ambos com eval_batch_size=256. Os 13 requests do
ensaio anterior reportaram exatamente 21 tokens de entrada e 256 de saída cada;
a carga representada cabe em ambos. Não se presume que a redução de contexto
reduza memória suficiente ou melhore TPS: esse é o próximo teste. Sem alterações
nos limites de admissão, swap, temperatura, jitter ou no piso de performance.
O workload recebeu nome separado para não sobrescrever perfis de rodadas anteriores.

Foi acrescentado `--output` à CLI para gravar atomicamente um relatório externo,
inclusive em falhas após sua inicialização. A divergência anterior entre arquivo
externo vazio e artefato interno não foi atribuída a uma causa sem evidência;
a escrita explícita pelo programa evita depender do redirecionamento do shell.
Testes verificam igualdade do arquivo com stdout na recusa de admissão e impedem
que o destino seja o próprio perfil de entrada.

A rodada proposta usará `.qualification/lmstudio-context/state` e
`.qualification/lmstudio-context/report.json`, preservando a evidência anterior.
A reserva e orçamento atuais exigem cerca de 5,07 GiB de RAM disponível; a coleta
ambiente registrou mínimo de 3,76 GiB. Aguardar admissão não reduz esse requisito.

## Contexto 2k/4k: fila expirou antes de carregar modelo

Artefato: `.qualification/lmstudio-context/report.json`, recebido em 2026-10-25.
A escrita explícita com --output funcionou no host: JSON válido, validation
incomplete, erro de admissão e zero runs. Não há comparação 2k versus 4k.

Após dois minutos, a última amostra tinha 4.440.100.864 bytes disponíveis contra
5.440.535.756 exigidos. Déficit: 1.000.434.892 bytes, aproximadamente 954,09 MiB.
A fila respeitou a reserva e o orçamento; aumentar o tempo não cria memória.

O orçamento adicional de 2 GiB continua provisório. A estimativa do backend de
962,09 MiB não é um pico medido, e não foi usada para reduzir automaticamente o
orçamento. Próximo diagnóstico solicitado: processos do usuário ordenados por
RSS, usando nomes curtos (sem argumentos ou credenciais). RSS compartilhado não
será somado como se fosse consumo exclusivo; o objetivo é identificar processos
para inspeção mais precisa, sem encerrar nenhum automaticamente.

## RSS por processo recebido em 2026-10-25

A lista recebida inclui processos Chromium, ChatGPT/codex, lm-studio, llama-server,
Dropbox, quickshell e claude-desktop. O maior RSS individual listado foi de um
processo Chromium (839028 KiB); llama-server apareceu com 392688 KiB e pai
lm-studio. Isso não demonstra vazamento, consumo exclusivo por aplicativo ou
modelo ainda carregado: um servidor de inferência pode continuar vivo sem modelo.
Nenhum processo foi encerrado e nenhum nome foi usado como alvo de ação automática.

Foi criado `tools/inspect_memory.py`, somente leitura e sem privilégios adicionais.
Ele reúne PSS/SwapPss quando acessíveis, mantém RSS como dado distinto, registra
cobertura da coleta e confirma loaded_instances pela API. Não lê cmdline/environ;
verifica start_time antes/depois para descartar reciclagem de PID. Agrupamento é por
nome exato de processo, sem inferência de árvore de propriedade da aplicação.
Referência consultada: [documentação /proc do kernel](https://docs.kernel.org/filesystems/proc.html),
seções smaps, PSS e smaps_rollup, em 2026-10-25.

Os testes locais cobrem PSS separado de RSS, cobertura ausente, UID e reciclagem de
PID; a suíte Python passou com 12 testes. O smoke no sandbox viu apenas nove
processos do namespace, portanto não é inventário do desktop real. Próxima coleta
solicitada no host: `.qualification/lmstudio-context/memory-host.json`. O orçamento
provisório de 2 GiB e a reserva de 20% permanecem inalterados enquanto essa hipótese
sobre memória residente é investigada.

## PSS e modelo residente confirmados no host

Artefato recebido: `.qualification/lmstudio-context/memory-host.json`,
2026-10-25T04:47:39Z, host skynet-omarchy. Foram vistos 144 processos do usuário,
com PSS indisponível para seis e coleta não truncada (0,26 s).
O PSS conhecido somou 2.187.175.936 bytes (2,037 GiB). Isso não é toda a memória
física do sistema: memória de kernel/GPU, outros usuários, cache e dados ausentes
não são contabilizados como se fossem PSS desses processos.

ZRAM usava 6.010.273.792 bytes físicos (5,598 GiB) para dados comprimidos;
o campo lógico de swap permaneceu separado. MemAvailable após a coleta:
6.331.748.352 bytes (5,897 GiB), acima dos 5.440.535.756 bytes exigidos pelo perfil
na topologia registrada. Não foi necessário diminuir orçamento ou reserva para
que essa fotografia satisfizesse a desigualdade de admissão.

A API informou uma instância `qwen3-0.6b` residente com contexto 8192, parallel 4
e eval_batch_size 2048. Isso é diferente do ensaio planejado e não pode ser usado
como baseline 2k/4k. O motivo/ator de sua carga não foi inferido. RSS/PSS baixo do
processo llama-server não foi usado para concluir que o modelo estivesse ausente.

O perfil `examples/lmstudio-context.json` agora declara `release_before` para
exatamente o modelo e instance_id `qwen3-0.6b`, no endpoint local. A operação
verifica modelo/ID, descarrega essa instância, confirma sua ausência no inventário
e depois reavalia a admissão antes de carregar cada candidato. Não descarrega
outros modelos nem encerra aplicativos. O teste de regressão verifica que uma
segunda instância de outro modelo permanece intocada.

A amostra isolada não garante RAM suficiente no momento do próximo ensaio; a fila
continuará usando os mesmos limites e checagens. Próximo ensaio: repetir o perfil
2k/4k já preparado com a liberação explícita, preservando os relatórios anteriores.


## Protocolo real LM Studio concluído — 2026-10-25

Artefato: `.qualification/lmstudio-context/report.json`, início 04:54:25Z.
Verificação independente: `assessment.json`; replay pelo comando `compare`
reproduziu a seleção. O relatório original foi preservado.

| Execução | Gerações | Tempo medido | TPS mediano | IC bootstrap 95% |
|---|---:|---:|---:|---|
| Baseline contexto 2048 | 14 | 121,16 s | 29,961 | 29,051–30,251 |
| Candidato contexto 4096 | 15 | 127,50 s | 30,219 | 29,934–30,342 |
| Rechecagem contexto 2048 | 15 | 128,11 s | 30,162 | 29,999–30,335 |

A liberação explícita da instância foi confirmada. As cargas confirmaram contexto
esperado e eval_batch_size 256. Nenhuma proteção interrompeu o protocolo; o tráfego
lógico de swap por execução ficou entre 90,69 e 95,55 MiB, abaixo de 256 MiB.
A temperatura máxima foi 82 °C, sem throttling detectado nos contadores disponíveis.

Fases 2 e 3 validadas no escopo deste modelo de controle, endpoint e protocolo.
Fase 7 exercitada com medições reais e replay; isso não comprova uma otimização:
a seleção 4k teve +0,86% contra o baseline inicial e +0,19% contra o final,
com intervalos sobrepostos. O jitter do timer não comprova responsividade do desktop.
Não extrapolar a GLM 30B, outros backends ou estabilidade térmica prolongada.
As fases ComfyUI/Docker permanecem sem homologação real.


## ComfyUI/Docker iniciado e integração real — 2026-10-25

Acesso ao Docker corrigido na sessão com `newgrp docker`: o cadastro do usuário
já incluía o grupo, mas os grupos suplementares da sessão estavam antigos.
Nenhuma permissão do socket ou associação permanente foi alterada.

Build local em `deploy/comfyui/Dockerfile`: ComfyUI commit
`19ae172bff6c9e4c738e7f2e00fe087f5b5b46ab` (0.42.0), Python base fixada por
digest, PyTorch 2.14.1+cpu e torchvision 0.29.1+cpu. As dependências transitivas
resolvidas foram salvas em `.qualification/comfyui/requirements-resolved.txt`.
A imagem executada foi fixada por ID completo:
`sha256:c4f8325b894abe5cad5fce5d32ff474351a1e7eff168844a80641c564b26779e`.
O inferctl agora aceita IDs locais completos além de digests de repositório;
`container.gpu=cpu` passa `--cpu` explicitamente.

`TestDockerIntegration` real passou em 13,08 s: memory/memory-swap 6.442.450.944
bytes, nenhuma quota de CPU, sete volumes persistentes e modelos LM Studio
externos readonly. Import torch e leitura/escrita persistentes verificadas;
o arquivo de saída sobreviveu à remoção do container temporário.
Log: `.qualification/comfyui/integration.log`.

A instância compose independente está em http://127.0.0.1:8188, CPU, offline,
UID do usuário, sem restart automático, sem socket Docker montado e sem swap
no container. Dados: `~/.local/share/inferctl/comfyui/`. Modelos existentes
montados readonly em `/external/lmstudio`, sem cópia.

API, frontend HTTP, submissão de grafo, histórico de sucesso, endpoint view e
PNG persistente 64x64 passaram (`smoke-result.json`, `smoke-history.json`).
O grafo usa EmptyImage/SaveImage: não executa inferência, não mede desempenho e
não homologa geração por IA. Fase 6 validada no escopo CPU/local; GPU não testada.
Fase 5 tem smoke de API real, mas homologação de geração permanece aberta.

No diretório informado pelo usuário foram encontrados somente Wan 14B GGUF e
Qwen 0.6B GGUF; nenhum workflow JSON, text encoder ou VAE separado. Não foi
carregado o Wan, instalado custom node nem baixado outro modelo. O caminho
GGUF de vídeo ainda requer workflow, componentes e orçamento de memória.
O build causou pressão temporária de disco; seus tempos não são benchmark de IA.

Parada reproduzível, preservando dados, a partir da raiz de inferctl numa sessão
com acesso ao Docker:

```bash
docker compose --env-file .qualification/comfyui/compose.env -f deploy/comfyui/compose.yaml down
```

Esse projeto compose não é registrado pelo calibrador; `inferctl reset` não
encerra esta instância. Use `down` antes de calibrar outro container na porta 8188.


## Correção de localização e descoberta GGUF — 2026-10-25

Por solicitação do usuário, o projeto inteiro, incluindo artefatos locais, foi
movido de `Dotfiles/inferctl` para `SamsungBook-Np550xda/Omarchy/inferctl`.
Não foi mantida cópia ou symlink no local anterior. Relatórios históricos
preservam caminhos e hashes originais; scripts locais ativos foram atualizados.
O README Omarchy agora aponta para o projeto.

Apenas montar `/external/lmstudio` não registrava modelos: o compose agora passa
`--extra-model-paths-config` com YAML readonly. Foi instalado ComfyUI-GGUF no
diretório persistente de custom nodes, commit
`6ea2651e7df66d7585f6ffee804b20e92fb38b8a`, archive checksum
`688126d5c2b8c4ff061f56b23c3c6791ac01dc366e98d41ef1aaef374c36f283`.
`install-gguf.sh` reproduz essa instalação e recusa sobrescrever um diretório
existente. A nova imagem inclui gguf==0.19.0. Fontes existentes não foram alteradas.

A API real `/object_info/UnetLoaderGGUF` confirmou na lista `unet_name`:
`nsfw_wan_14b_e15_q4_k.gguf`. Evidência:
`.qualification/comfyui/gguf-object-info.json`. Qwen não foi registrado como modelo
de difusão. Nenhum peso de 14B foi carregado; descoberta não é geração homologada.
O nó apropriado na interface é Unet Loader (GGUF).

Foi configurado `--temp-directory /app/ComfyUI/temp` para que ComfyUI use um
subdiretório gravável dentro do bind mount, em vez de tentar remover sua raiz.


## Localização final solicitada

Projeto movido para `SamsungBook-Np550xda/Omarchy/calibration/inferctl`.
README e scripts ativos atualizados; artefatos históricos preservados.
