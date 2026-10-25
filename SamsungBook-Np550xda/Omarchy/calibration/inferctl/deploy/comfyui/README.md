# ComfyUI local em CPU

Esta instalação valida o caminho Docker em máquinas sem acelerador PyTorch
confirmado. Não representa uma recomendação de desempenho para vídeo.
ComfyUI está fixado por commit e checksum; Python por digest; torch/torchvision
por versão CPU. As demais dependências são resolvidas no primeiro build e
registradas em `/app/requirements-resolved.txt`. O ID completo da imagem fixa
os bytes efetivamente executados; rebuilds não são considerados idênticos.

A partir da raiz de `inferctl/`, em uma sessão com acesso ao Docker:

```bash
docker build -t inferctl/comfyui:cpu-19ae172 deploy/comfyui
mkdir -p .qualification/comfyui
export COMFY_IMAGE="$(docker image inspect --format '{{.Id}}' inferctl/comfyui:cpu-19ae172)"
export COMFY_UID="$(id -u)" COMFY_GID="$(id -g)"
export LMSTUDIO_MODELS="$HOME/.lmstudio/models"
export COMFY_DATA="$HOME/.local/share/inferctl/comfyui"
mkdir -p "$COMFY_DATA"/{models,custom_nodes,input,output,user,workflows,temp}
bash deploy/comfyui/install-gguf.sh # first install only; refuses to overwrite
docker compose -f deploy/comfyui/compose.yaml up -d
curl -fsS http://127.0.0.1:8188/system_stats
```

Se a sessão não recebeu o grupo `docker`, mas `id "$USER"` já o inclui,
`newgrp docker` abre uma sessão com a associação atualizada. Não é necessário
alterar permissões do socket nem executar ComfyUI como root.

O compose limita RAM a 10 GiB e RAM + swap a 24 GiB. Os limites podem ser
ajustados por `COMFY_MEMORY_LIMIT` e `COMFY_MEMORY_SWAP_LIMIT`. OpenMP/MKL
usam quatro threads e o cache intermediário está desativado para reduzir retenção
de pesos em CPU. A execução de vídeo é lenta e deve ser verificada por modelo.
Não aplica quota rígida de CPU.
A API só é publicada no loopback. Os sete diretórios persistem após remoção.
O serviço persistente usa `restart: unless-stopped`: o Docker reinicia o
container após a saída do processo e quando o daemon volta. Uma parada manual
permanece respeitada. Habilite `docker.service` no boot da máquina; os
containers temporários do calibrador continuam sem reinício automático para
não invalidar benchmarks ou ressuscitar workloads encerrados.
Custom nodes exigem instalação explícita, como o helper ComfyUI-GGUF no comando
acima. Não há gerenciador de custom nodes nem download automático de modelos.
Os limites de memória, as quatro threads e o cache desativado são escolhas deste
piloto em CPU; ainda precisam de comparação para determinar seu custo em tempo
de geração. O compose permite swap e não aplica o orçamento de admissão do
calibrador a esta instância independente.

Para parar e remover somente esta instalação, preservando os dados:

```bash
docker compose -f deploy/comfyui/compose.yaml down
```

O compose é independente dos containers temporários do calibrador: use `down`
antes de calibrar um perfil gerenciado na mesma porta. `inferctl reset` controla
somente recursos registrados pelo inferctl, não este projeto compose.

Receber `/system_stats` e executar um grafo sem modelo são smoke tests de
infraestrutura. A homologação de geração exige checkpoint real, workflow API
fixado, seed, warm-up, repetições, telemetria e comparação antes/depois.

O diretório LM Studio é montado somente leitura em `/external/lmstudio`.
Isso evita cópias; não torna um GGUF automaticamente compatível com os nós
nativos. Workflows GGUF podem exigir custom nodes e componentes adicionais.


`extra_model_paths.yaml` registers the existing Wan directory under
`diffusion_models`. ComfyUI-GGUF is pinned at
`6ea2651e7df66d7585f6ffee804b20e92fb38b8a`; its dependency gguf==0.19.0 is
included in the image. Use **Unet Loader (GGUF)** (`UnetLoaderGGUF`), not the
regular checkpoint loader. The Wan file should appear in its `unet_name` list.
LLM files such as Qwen are not Wan text encoders and are not registered there.
Discovery does not prove the weights load or fit RAM; model discovery must not be used to infer successful video
qualification. The current CPU limits allow swap; only an actual completed
workflow qualifies inference. Configure the matching text encoder, VAE and workflow separately.
