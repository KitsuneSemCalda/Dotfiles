# inferctl

Governador e calibrador local para Linux. Compara throughput antes de recomendar
limites, mantém um piso de performance e preserva os resultados brutos.

Ferramenta para uso pessoal supervisionado. Os testes incluem servidores
sintéticos e registros do host com LM Studio (Qwen3-0.6B), controles transitórios
do systemd e Docker em CPU. A comparação Qwen não demonstrou ganho reproduzível;
o smoke test do ComfyUI executou um grafo sem modelo de IA. Geração de imagem/vídeo,
containers GPU, thermal tuning e speculative decoding ainda precisam de ensaios.
Consulte [o estado por fase e as limitações](docs/validation.md).

```bash
cd inferctl
make check
make build
./bin/inferctl hardware
./bin/inferctl calibrate lmstudio --model CHAVE_EXATA --ram-bytes 4294967296 --dry-run
```

Go 1.23+ e biblioteca padrão; sem serviços, banco de dados ou dependências Go
externas. Não há instalação automática. JSON foi escolhido para perfis porque
permite validação estrita sem acrescentar um parser TOML.

O orçamento de RAM acima é **ilustrativo**, não uma estimativa para qualquer
modelo. `required_ram_bytes` deve representar a demanda adicional de RAM do
workload, incluindo KV cache e draft quando existirem. O programa recusa iniciar
sem esse orçamento. Descobrir com segurança o pico de um modelo desconhecido
continua sendo responsabilidade do piloto.

## Primeiro benchmark

1. Ligue o servidor do LM Studio/llmster, disponível em `127.0.0.1:1234`.
2. Obtenha a chave exata do modelo instalado em `GET /api/v1/models`.
3. Copie e ajuste [examples/lmstudio.json](examples/lmstudio.json), especialmente
   modelo, RAM, contexto, prompt e limites térmicos adequados ao hardware.
4. Descarregue explicitamente modelos residentes antes do teste exclusivo.
5. Examine o plano e execute:

```bash
./bin/inferctl calibrate lmstudio --profile profile.json --dry-run
./bin/inferctl calibrate lmstudio --profile profile.json
```

Se o servidor exigir autenticação, defina `INFERCTL_API_TOKEN` no ambiente. O
programa não grava o token. Para um servidor nativo iniciado pelo systemd, o
ambiente do gerenciador de usuário é distinto do ambiente deste cliente; configure
o servidor separadamente. Redirecionamentos HTTP são recusados.

Há warm-up, pelo menos três execuções e 120 segundos medidos por candidato,
mais uma repetição do baseline ao final. Baseline e candidatos usam o mesmo prompt,
contexto e orçamento de tokens. A busca inicial do LM Studio varia eval batch;
um refinamento limitado divide os intervalos ao redor do melhor ponto seguro.
Mantenha contexto adequado ao workload: o template usa 4096, sem aumentar
contexto por conta própria. Para testar outros contextos, forneça candidatos
explícitos e um prompt representativo que caiba em todos eles.

`bench` mede só o primeiro candidato. `--min-seconds 0` permite verificar o
protocolo rapidamente, mas **não salva perfil recomendado**. Tempos menores que
120 segundos são marcados como exploratórios. O timeout vale para cada candidato.

`--wait-admission 2m` aguarda até dois minutos por admissão, por candidato,
e pela trava local, sem reduzir orçamento ou reserva. Sem essa opção,
`calibrate` e `bench` recusam imediatamente; `run` mantém sua espera padrão.
`--output caminho/report.json` salva o relatório final ou de falha atomicamente
pelo programa, além do arquivo interno; o diretório é criado se necessário.
O destino deve ser JSON e diferente do perfil de entrada.
Após o relatório ser inicializado, falhas também produzem JSON em stdout, com
`error` e recomendação vazia, além do arquivo interno. O exit code continua
indicando falha: redirecionar stdout não significa que o benchmark passou.

## Processos nativos e llama.cpp

[examples/llamacpp.json](examples/llamacpp.json) inicia um `llama-server` por
candidato em um serviço transitório do systemd de usuário. Edite todos os caminhos
e orçamentos. Não é necessário root, mas o gerenciador de usuário e a delegação
dos controladores cgroups v2 precisam funcionar.

```bash
./bin/inferctl calibrate llamacpp --profile native.json --dry-run
./bin/inferctl calibrate llamacpp --profile native.json
./bin/inferctl calibrate llamacpp --profile native.json --thermal
./bin/inferctl calibrate llamacpp --profile native.json --draft-model /models/draft.gguf
```

A busca automática testa threads físicos, lógicos, metade dos físicos e uma
contagem baseada na reserva percentual de CPU, removendo duplicatas. Isso gera
experimentos; não presume que uma contagem será melhor. `--thermal` é um
experimento separado de pelo menos 300 segundos por candidato, comparando ausência
de quota com 90% e 100% da capacidade lógica. No systemd, 100% de CPUQuota significa
**um core**; o cálculo multiplica pelo número de threads lógicos.

`--draft-model` aceita até oito caminhos separados por vírgula e testa dois
comprimentos de draft por modelo. A versão instalada precisa suportar as flags
registradas no plano. Um candidato especulativo só pode vencer se seu intervalo
bootstrap de mediana ficar acima do intervalo do baseline. Os timings adicionais
que o servidor expuser são preservados; taxa de aceitação não exposta permanece
desconhecida. Os modelos não são baixados pelo inferctl.

Parâmetros nativos como mmap/mlock, Flash Attention, KV cache e offload podem ser
comparados através de `candidates[].args`. O comando é uma lista de argumentos,
executada sem shell. Consulte `llama-server --help` da versão instalada. O servidor
é reiniciado a cada candidato. O modelo principal deve permanecer o mesmo.
Alterações de quantização ou precisão precisam de validação de qualidade externa;
o programa não avalia equivalência semântica ou visual.

`CPUWeight`, `IOWeight`, `MemoryHigh`, `MemoryMax`, `MemorySwapMax`, `Nice` e ionice (`io_nice_priority`, opcional, 0–7) são
propriedades transitórias; CPUQuota só aparece quando configurada ou no experimento
térmico. O perfil deve fornecer limites adequados: a reserva de RAM é usada na
admissão e não é convertida automaticamente em um MemoryMax. Não há alterações de
sysctl, governor global ou arquivos permanentes do sistema.

Os controles de CPU e memória são conferidos nos arquivos reais do cgroup antes
do benchmark. Se `io.weight` não existir, o peso neutro `io_weight=100` permite
continuar com `capability.io_weight` marcado como indisponível no relatório.
Um peso diferente de 100 exige verificação; `require_io_weight=true` exige o
controle mesmo no valor padrão. Isso não comprova priorização de I/O neste host.

Um servidor que já estava rodando pode ser medido, mas não recebe limites nem
argumentos de inicialização. O programa recusa configurações que alegariam aplicar
esses controles a um processo externo. Não adota nem descarrega modelos previamente
residentes no LM Studio. Um serviço gerenciado precisa de uma porta livre.

## ComfyUI e Docker

Para construir e iniciar uma instalação local em CPU, consulte
[deploy/comfyui](deploy/comfyui/README.md). Esse caminho inclui Dockerfile
fixado por commit/checksum, compose e dados persistentes.

Exporte o workflow no **formato API**. Informe os inputs de seed como `3.seed` ou
`25.noise_seed`; todos devem existir e ser numéricos. O mesmo cronograma de seeds é
usado entre configurações. Seeds de warm-up são separados. Um nó de seed que tenha
sido atendido pelo cache invalida a medição. Cache de etapas independentes da seed
permanece permitido e registrado.

```bash
./bin/inferctl calibrate comfyui --workflow /work/workflow_api.json \
  --seed-node 3.seed --ram-bytes 4294967296 --dry-run
```

Para medir um servidor externo, retire `container` do perfil. Para testar opções
de inicialização, use um `command` nativo ou o container em
[examples/comfyui.json](examples/comfyui.json). A imagem ilustrativa **não existe**:
escolha uma imagem compatível com seu hardware, já presente localmente, e substitua
pelo digest real. O inferctl não escolhe, baixa ou constrói imagens e não usa
`latest`. Imagens construídas localmente também podem ser fixadas pelo ID completo
`sha256:...` obtido em `docker image inspect --format '{{.Id}}' IMAGEM`.
A imagem precisa conter Python, PyTorch, ComfyUI e suas dependências;
`app_path` indica onde seu `main.py` está instalado.

Crie e ajuste sete diretórios persistentes no `data_root`: `models`, `custom_nodes`,
`input`, `output`, `user`, `workflows`, `temp`. O container usa seu UID/GID, porta
exposta só em loopback e `--rm`. A montagem de `custom_nodes` substitui o diretório
da imagem: mantenha ali os nós exigidos pelo workflow. Não monta o socket Docker.

```bash
./bin/inferctl docker-plan comfy.json
./bin/inferctl calibrate comfyui --profile comfy.json
```

`container.gpu`: `cpu`, `nvidia`, `amd` ou `intel`. NVIDIA exige runtime compatível;
AMD/Intel exigem `devices` explícitos e, quando necessário,
`supplementary_groups` com GIDs numéricos para acesso aos render nodes. A imagem
precisa ter o backend PyTorch apropriado. `container.cpus` é quota opcional;
`memory_bytes` limita RAM e desabilita swap do container. Estes limites são
independentes dos limites systemd: tentar usar os últimos com Docker é erro.

Para reutilizar modelos externos sem cópia:

```json
{
  "model_mounts": {"shared": "/home/user/AI/models"},
  "extra_model_paths_config": "/home/user/AI/extra_model_paths.yaml"
}
```

Essas chaves pertencem a `container`. As pastas são montadas somente para leitura
em `/external/shared`. O YAML deve referenciar esse caminho interno, por exemplo:

```yaml
shared:
  base_path: /external/shared
  checkpoints: checkpoints
  diffusion_models: diffusion_models
  vae: vae
```

A busca automática compara quatro valores de `--reserve-vram`. Para comparar
cache, atenção ou async offload, use candidatos explícitos com `args`, mantendo
workflows, steps, resolução e seeds iguais. Flags dependem da versão da imagem;
uma flag indisponível causa falha de inicialização, nunca sucesso silencioso.
`images_per_run` e `frames_per_run`, quando conhecidos e informados no perfil,
habilitam métricas por imagem/frame. Não são inferidos de workflows arbitrários.

## Seleção, observação e recuperação

- Piso de performance: `quality.min_performance_ratio`, padrão 0.90, contra baseline
  e melhor candidato seguro. Para ComfyUI, performance é `1 / segundos`.
- Restrições: falha/OOM, swap do host, temperatura, TTFT e jitter de agendamento no
  modo interactive. Sensor térmico ausente impede recomendação automática.
- Seleção: frente Pareto; interactive escolhe menor jitter e depois temperatura
  entre os candidatos que passaram pelo piso. batch/idle/night escolhem throughput.
- Swap: o padrão `quality.swap_accounting="total"` (também usado quando omitido)
  limita a ocupação total do host. O modo explícito `"additional"` limita,
  separadamente, crescimento de ocupação e soma do tráfego novo de swap-in/out,
  desde antes da carga e warm-up. Ambos usam o mesmo `max_host_swap_bytes`;
  o relatório preserva ocupação total, baseline e contadores. Tráfego do host não
  é atribuível exclusivamente ao modelo. Esse modo não prova que o histórico de
  swap seja inofensivo e não altera swap ou configurações do sistema.
- Medidas: mediana, p05/p95, intervalo bootstrap, séries de execuções, razão de
  throughput entre as metades inicial/final e repetição final do baseline.
- RAM, swap, CPU e VRAM observados no host incluem outros processos. Para serviços
  nativos gerenciados, os contadores separados de cgroup incluem memória, faults,
  I/O e OOM. Energia disponível é somente GPU, não consumo total da máquina.
- Jitter é atraso de um timer em goroutine independente do polling dos sensores.
  **Não mede latência real de teclado, compositor ou desktop.**

Resultados e eventos vão para `INFERCTL_STATE`, ou
`$XDG_STATE_HOME/inferctl` (padrão `~/.local/state/inferctl`). Os caminhos incluem
hardware, backend, modelo/revisão, conteúdo do workload e modo. Um perfil recomendado
fica vinculado ao hardware medido; `model_revision` permite distinguir revisões
com a mesma chave de modelo. Perfil recomendado é salvo
separadamente e nunca ativado automaticamente. Prompts e caminhos fazem parte dos
relatórios; guarde esse diretório como dado pessoal.

```bash
./bin/inferctl compare /path/report.json
./bin/inferctl run --profile recommended.json --dynamic
./bin/inferctl reset
```

`run` aguarda a trava de admissão e RAM/VRAM suficientes, executa um workload de
benchmark limitado e termina. Ainda não é uma fila persistente de jobs nem um
daemon autônomo. Todos os workloads iniciados pelo inferctl são serializados,
mesmo quando `exclusive` é falso; isso evita contenção durante calibração.
`--dynamic` funciona apenas com serviços nativos e aplica hysteresis de 30 segundos
na CPUWeight ao detectar pressão de RAM ou temperatura. Exige
`policy.pressure_cpu_weight` explicitamente configurado a partir de uma medição;
não aplica um percentual de redução fixo presumidamente melhor. Não detecta atividade
real do desktop e não altera limites rígidos de memória. Os resultados dinâmicos
não geram recomendações de configuração fixa.

Ctrl-C tenta descarregar apenas a instância carregada por esta execução e encerra
seus serviços/containers. `reset`, sem uma execução concorrente, encerra somente
unidades/containers com registros de propriedade do inferctl. Isso também reverte
Nice e todos os limites ao encerrar o processo pertencente ao programa. Não toca
modelos, saídas ou processos arbitrários. Um workflow em servidor ComfyUI externo
pode continuar após timeout: não é usado o `/interrupt` global, que atingiria
trabalho de outros clientes. Verifique seu prompt ID antes de reenviar.

Para um handoff exclusivo de LM Studio para ComfyUI, `release_before` permite
nomear explicitamente instâncias que podem ser descarregadas:

```json
"release_before": [{
  "backend": "lmstudio",
  "url": "http://127.0.0.1:1234",
  "model": "chave-exata-do-modelo-30b",
  "instance_id": "id-exato-obtido-no-inventario"
}]
```

Exige `policy.exclusive=true`. O programa verifica modelo e instância, solicita
unload, confirma ausência no inventário e só depois verifica RAM/VRAM disponíveis.
Uma instância de outro modelo causa recusa. Essa lista é autorização explícita do
perfil; modelos não listados não são descarregados. Não há evicção automática de
modelos desconhecidos nem garantia contra outros programas iniciados fora do
inferctl enquanto ele está executando.


O [perfil de controle pequeno](examples/lmstudio-control.json) é uma bancada
para validar o caminho de benchmark: Qwen3-0.6B Q8_0, contexto 4k, orçamento de
admissão de 2 GiB, dois candidatos de batch e o modo explícito de swap adicional.
O orçamento é um limite planejado de admissão, não um pico medido nem um limite
imposto a um servidor externo. Confirme a chave pela API e a estimativa do backend
antes de executar. Passar nessa bancada não homologa GLM 30B ou workloads de vídeo.


Para investigar uma recusa por swap, sem iniciar inferência ou alterar o sistema:

```bash
python3 tools/observe_pressure.py --duration 120 \
  --output .qualification/lmstudio-control/ambient-host.json
```

O coletor grava um arquivo próprio com taxas de swap-in/out, PSI e estatísticas
por dispositivo. ZRAM é identificada como RAM comprimida; ocupação lógica e uso
físico ficam separados. A observação é do host, não uma atribuição a um processo.
Uma amostra posterior não pode ser subtraída de um benchmark anterior para
atribuir causalidade. Ela ajuda a desenhar um controle comparável na próxima rodada.


`examples/lmstudio-parallel1.json` é um experimento separado de concorrência máxima
para a mesma bancada pequena. `load.parallel` é uma opção experimental na API REST:
o CLI oficial oferece esse controle, mas a documentação REST consultada não o
lista. Só é aceito como aplicado quando o backend devolve exatamente o valor
solicitado em `load_config`. Não há fallback silencioso nem garantia de economia
de memória. Compare primeiro `lms load --estimate-only` e depois as medições reais.


O perfil `examples/lmstudio-context.json` compara contexto 2048 (baseline) e 4096,
com batch 256 e os mesmos limites. É um experimento para o prompt curto da bancada:
os requests anteriores reportaram 21 tokens de entrada e 256 de saída. Não use
esse resultado para recomendar contexto 2k a prompts maiores. Na sessão registrada,
admitir o orçamento de 2 GiB mais a reserva de 20% exigia aproximadamente 5,07 GiB
de RAM disponível antes da carga; esperar não reduz esse requisito.

Para um censo rápido de memória dos processos do usuário, sem carregar modelos:

```bash
python3 tools/inspect_memory.py \
  --output .qualification/lmstudio-context/memory-host.json
```

O relatório inclui PSS de `smaps_rollup` quando permitido, swap proporcional
lógica separada de RAM/ZRAM e inventário somente de leitura da API. Não registra
argumentos nem ambientes dos processos. Nomes iguais são agrupados, sem presumir
que representem uma única aplicação. PSS inacessível fica marcado como desconhecido;
o coletor não pede root. O censo é uma fotografia não atômica, não uma medida de
pico do modelo. PIDs reciclados durante a leitura são descartados.

O perfil de ensaio `examples/lmstudio-context.json` inclui `release_before` para
`qwen3-0.6b` com instance_id `qwen3-0.6b`: ao executá-lo, essa instância conhecida
pode ser descarregada antes da comparação. A liberação é por modelo/ID exatos,
verificada pela API, e não se estende a outros modelos ou aplicativos. Adapte essa
lista explicitamente se usar uma instância diferente.
