# Captura local: Samsung Book NP550XDA

## Estado medido em 2026-10-12 (Omarchy)

O i5-1135G7 usa uma única Iris Xe para jogo, compositor, OBS e codificação. O
monitor interno é 1920×1080. PipeWire 1.6.8, WirePlumber 0.5.17,
`xdg-desktop-portal` e `xdg-desktop-portal-hyprland` estavam ativos. OBS
32.2.2 carregou `linux-pipewire.so`, `obs-qsv11.so` e `obs-ffmpeg.so`.
O OBS anunciou `obs_qsv11_v2` (H.264), `obs_qsv11_hevc`, VA-API H.264 e
VA-API HEVC; o ID antigo `obs_qsv11` está depreciado.
`vainfo` no `/dev/dri/renderD128`, com Intel iHD, anunciou H.264 e HEVC
`EncSlice`; anunciou AV1 apenas como `VLD` (decodificação). Um encoder
aparecer no FFmpeg ou existir como plugin não comprova que o OBS conseguirá
inicializá-lo durante uma gravação: faça o teste abaixo.

A webcam interna `VGA Camera` aparece como nó de vídeo PipeWire, mas V4L2
anunciou somente YUYV até **640×480 a 30 FPS**. Use esse modo nativo. Para
1280×720 a 30 FPS é preciso outra câmera. Não há MJPEG/H.264 na webcam
interna, portanto não há decodificação de câmera a acelerar.

## Caminho de vídeo

Use no OBS `Screen Capture (PipeWire)` para monitor e `Window Capture
(PipeWire)` para janela. O portal pede consentimento na primeira seleção.
Uma escolha de janela pode depender do compositor e da aplicação. Prefira
monitor quando uma janela não surgir. Não use `XSHM` como caminho padrão.

O PipeWire pode negociar DMA-BUF com o portal e OBS, mas isso depende do
formato, modificadores e importação pelo OBS. Esta configuração **não garante
zero-copy**: OBS ainda compõe cenas e pode haver conversão/cópia antes do
encoder. Compare `OBS Stats` e logs com monitor e janela; escolha o caminho
que renderiza sem atraso na carga real. Evite filtros e scaling em fontes.

## Perfis OBS

Os perfis ficam em `basic/profiles/` e a coleção em `basic/scenes/`. O
instalador de cada sistema copia os arquivos individualmente e protege
edições locais com backup. Feche OBS antes de instalar. Em Linux, execute
`perl Omarchy/omarchy.pl --dry-run` e depois `--backup`; no Windows use
`Windows-11/win11.ps1 -DryRun` e depois `-Backup`. Selecione a coleção
`Capture Infrastructure` e um perfil pelo menu do OBS.

| Perfil | Vídeo | QSV H.264 CQP | Uso |
| --- | --- | --- | --- |
| Desktop Development | 1080p60 | 18, TU4 | Texto e demonstrações |
| Light Gameplay | 1080p60 | 21, TU6 | Jogos leves |
| Heavy Gameplay | 720p60 | 24, TU7 | Primeira opção quando a GPU satura |

Todos usam 48 kHz, MKV, cinco tracks e remux automático para MP4. Os valores
CQP 18/21/24 são pontos de partida, não qualidade garantida; números menores
produzem arquivos maiores. Se o perfil pesado ainda atrasar, teste 900p60
e 1080p30 como variações do perfil, uma mudança por vez. Não ative rescale
na saída; a resolução do perfil já define o tamanho final. HEVC pode reduzir
espaço, mas H.264 foi escolhido por compatibilidade. AV1 não é opção de
encoding neste chip. ICQ é alternativa a comparar com CQP no OBS; LA-ICQ
acrescenta trabalho e só deve entrar após medição.

Streaming usa um encoder QSV H.264 separado, CBR 6000 kb/s em 1080p60 nos
perfis Desktop/Light e 4500 kb/s em 720p60 no Heavy, keyframe de 2 s e áudio
AAC no track 5 (mix final). Ajuste bitrate e resolução depois de medir a
conexão e os limites do destino; gravação local continua CQP/MKV. O
`user.ini` já seleciona perfil e coleção e marca o primeiro uso como concluído,
dispensando o assistente. A conta/servidor e a chave de streaming não entram
nos dotfiles: configure-os localmente no OBS antes de iniciar a transmissão.

Os nomes dos cinco tracks são: Microphone, Game-System, Discord-Chat, Music,
Final-Mix. `RecTracks=31` habilita os cinco, mas a atribuição de cada fonte
de áudio em **Advanced Audio Properties** depende dos dispositivos reais:

| Fonte | Track separado | Mix final |
| --- | --- | --- |
| Microfone processado | 1 | 5 |
| Jogo/sistema | 2 | 5 |
| Discord/chat | 3 | 5 |
| Música | 4 | 5 |

Desative as fontes globais de desktop/microfone, como os perfis fazem, para
evitar dupla captura. No Linux as quatro fontes PipeWire já estão em `Audio
Buses` com as tracks acima; confirme que seus medidores respondem. No Windows
adicione as entradas dos aplicativos a essa cena e atribua as tracks em
Advanced Audio Properties. A coleção também inclui `Capture
Monitor`, `Capture Window` e `Camera PiP` reutilizáveis. Associe a fonte de
portal em cada cena de captura na interface do OBS; a autorização do portal
não pode ser gravada como dotfile portátil. As fontes de monitor e janela
já existem nas cenas, mas a primeira seleção pode abrir o diálogo do portal.
No Omarchy, `Camera Device` vem associado à webcam interna PipeWire detectada
neste Samsung Book (YUY2, 640x480 a 30 FPS). A PiP fica no canto inferior direito,
acima da captura principal. `Camera Fullscreen` amplia a imagem 4:3 até a
altura do canvas 1080p, com barras laterais. No Windows, selecione a câmera
local uma vez em `Camera Device`, pois o ID DirectShow varia entre máquinas.
`Starting`, `BRB` e `Ending` incluem telas com título e fundo escuro. Se a
câmera for trocada, selecione o novo nó em `Camera Device`; as duas cenas de
câmera compartilham a mesma fonte.

## Roteamento de áudio Linux

`capture-audio start` cria três sinks PipeWire via compatibilidade Pulse:
`capture_game`, `capture_chat`, `capture_music`. As fontes de captura no OBS
são os respectivos `.monitor`. O script também cria `capture_microphone`,
um microfone virtual que parte da fonte padrão. Use `pavucontrol`/`wpctl`
para enviar cada aplicação ao sink certo; cada bus retorna ao sink físico que
era o padrão ao iniciar o serviço. Não mude o sink padrão do sistema. Se
trocar de fones/alto-falantes, reinicie o serviço para atualizar o retorno.
`capture-audio status` lista os nós; `capture-audio stop` descarrega apenas
os módulos criados pelo script. O serviço `capture-audio.service` os cria
no login e os remove no logout; após reiniciar PipeWire, reinicie o serviço.

O microfone virtual inicial é **sem filtros**. O microfone interno estava
mutado na inspeção e o microfone dinâmico externo ainda não foi identificado;
ligar um filtro fixo ao dispositivo errado criaria silêncio. Quando o
microfone externo estiver conectado, selecione-o como fonte padrão, recrie
`capture_microphone` e valide o nível. Para processamento, use EasyEffects
no grafo PipeWire com HPF 70–90 Hz, expander leve, EQ somente após ouvir,
compressão moderada e limiter de segurança. Salve o preset só após medir
ruído, ganho e clipping desse microfone. Evite gate duro. EasyEffects foi
instalado depois da inspeção, mas ainda não há preset calibrado nem
microfone externo para avaliar sua cadeia de entrada.

## Windows 11

Os mesmos três perfis QSV H.264/MKV e a coleção de cenas são instalados em
`%APPDATA%\obs-studio`. No Windows use Game Capture quando funcionar bem,
Display/Window Capture para desktop, DirectShow para câmera e WASAPI para
microfone. O equivalente ao roteamento por aplicativo é `Application Audio
Capture` no OBS; selecione jogo, Discord e música separadamente e deixe
`Desktop Audio` global desativado. Os caminhos PipeWire/portal e os IDs dos
dispositivos são exclusivos do Linux e não se aplicam ao Windows.

## Benchmarks e ajuste

Faça cada cenário por pelo menos 10 minutos, com a mesma carga e resolução.
Para revelar throttling térmico, repita gameplay por 20–30 minutos. Use
`python3 Omarchy/scripts/capture-benchmark.py nome --seconds 600 --output
resultados/nome.csv` ou `Windows-11/scripts/capture-benchmark.ps1`. Durante o
teste anote em `OBS Stats` lag de renderização, lag de encoding e frames
perdidos; copie as porcentagens para o CSV. A amostragem do script cobre RAM,
temperatura, frequência e memória do OBS no Linux. `intel_gpu_top` e
MangoHud são opcionais e devem ser instalados apenas se faltarem; registre
GPU busy e frametime separadamente. `pw-top` e `journalctl --user` ajudam
a investigar XRUNs. No Windows, use Task Manager/Performance Monitor para
GPU, frametime e temperatura.

Ordem de cenários: desktop sem OBS; desktop+OBS; +webcam; jogo sozinho;
jogo+OBS; +webcam; +processamento do microfone. Compare baseline e cada
adição. Teste preview ligado/desligado e FPS cap do jogo em 60 e abaixo de
60 com MangoHud ou limitador do jogo. Reserve margem na Iris Xe; se o jogo
saturar a GPU, baixe o FPS/resolução do jogo ou use o perfil pesado antes de
reduzir ainda mais o CQP. Aceitação: lag de renderização <1%, lag de
encoding <1%, perda ≈0%, sem XRUNs audíveis e frametime do jogo previsível.

Um teste isolado de FFmpeg/VA-API codificou 1200 frames sintéticos 1080p60
em 4,23 s (4,72× tempo real); FFmpeg/QSV codificou 600 frames em 3,15 s
(3,16×). Isso confirma H.264 por hardware nos dois caminhos, sem medir o
custo de capturar e compor no OBS. Nesta sessão não havia OBS aberto nem jogo rodando. Os números de lag,
frametime, temperatura sustentada e efeito do preview ainda exigem esses
cenários reais; não são inferidos de `vainfo`.

## Referências

- [Guia de gravação e MKV do OBS](https://obsproject.com/kb/standard-recording-output-guide)
- [Configurações de QSV do OBS](https://github.com/obsproject/obs-studio/blob/master/plugins/obs-qsv11/obs-qsv11.c)
- [Captura de áudio por aplicativo no Windows](https://obsproject.com/kb/application-audio-capture-guide)
- [Filter-chain do PipeWire](https://docs.pipewire.org/page_module_filter_chain.html)
