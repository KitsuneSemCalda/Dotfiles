# TODO — Dotfiles

Backlog das correções identificadas na auditoria de 2026-09-17. As tarefas
estão ordenadas por risco e dependência. Cada tarefa deve ser implementada e
verificada separadamente.

**Status (2026-09-17):** todas as 7 tarefas foram implementadas, cada uma em
commit(s) atômico(s) revisáveis no histórico do git. `perl -c`, `docker
compose config`, `git diff --check`, e testes ponta-a-ponta em `$HOME`
temporário confirmam o comportamento do lado Omarchy/Perl e do Docker. **O
lado Windows/PowerShell não pôde ser executado ao vivo** (`pwsh` não estava
disponível no ambiente e a instalação via AUR ficou bloqueada por exigir
senha de sudo interativa); essas mudanças foram verificadas por revisão
manual cuidadosa do código e comparação linha a linha com o comportamento
original, mas os itens de verificação que exigem rodar `win11.ps1` de fato
continuam marcados como pendentes abaixo até alguém rodar em uma máquina com
PowerShell.

## Prioridade alta

### 1. Corrigir o restore do Windows

O `Restore-Backups` atual reconstrói o destino concatenando o caminho relativo
do backup com `$Target`. Isso ignora `Get-LinkMap` e restaura GlazeWM,
Starship, o perfil PowerShell e Rainmeter em caminhos diferentes dos usados na
instalação. Os backups modificados pelo tema também precisam voltar aos seus
destinos reais.

**Critérios de aceite:**

- [x] O restore consulta um mapeamento explícito entre cada item do backup e
      seu destino original. (`manifest.json` por snapshot; commit `5169ac3`,
      completado em `a8609b5`)
- [x] GlazeWM, Starship, perfil PowerShell e `AincradHUD` voltam exatamente aos
      caminhos usados por `Install-Symlinks`.
- [x] `settings.json` do Windows Terminal e `Rainmeter.ini` voltam aos caminhos
      de onde foram copiados.
- [x] O restore detecta conflitos antes de remover ou sobrescrever arquivos.
      (passagem de validação por hash SHA-256 antes de qualquer alteração)
- [x] `-Restore -DryRun` mostra os destinos reais sem alterar o sistema.

**Verificação:**

- [ ] Criar um teste com `$Target` temporário contendo arquivos preexistentes.
- [ ] Executar instalação com `-Backup`, alterar os destinos e executar
      `-Restore`.
- [ ] Comparar conteúdo, tipo e caminho de cada item antes e depois do ciclo.
- [ ] Confirmar que um conflito aborta o restore sem mudanças parciais.

  *(Não executado: requer `pwsh`, indisponível neste ambiente. O equivalente
  Omarchy/Perl do restore foi testado ponta a ponta com sucesso — ver tarefa 2.)*

**Arquivos prováveis:**

- `SamsungBook-Np550xda/Windows-11/win11.ps1`
- `SamsungBook-Np550xda/Windows-11/README.md`
- `SamsungBook-Np550xda/docs/architecture.md`

**Dependências:** nenhuma.

## Prioridade média

### 2. Tornar instalação e restore de links transacionais

Os instaladores Omarchy e Windows podem criar links antes de encontrar um
conflito posterior. Separar validação e aplicação evita instalações parciais.

**Critérios de aceite:**

- [x] Uma primeira passagem valida todas as origens, destinos e operações de
      backup sem alterar arquivos. (commit `c398880`)
- [x] A aplicação só começa quando nenhuma validação bloqueante falhar.
- [x] Falhas durante a aplicação produzem uma mensagem que identifica as
      mudanças já realizadas e não afirmam que nada foi alterado.

**Verificação:**

- [x] Testar HOME temporário sem conflitos. *(Omarchy/Perl, ao vivo)*
- [x] Testar conflito (Omarchy/Perl, ao vivo — `.config/starship.toml` como
      arquivo pré-existente; validação coleta todos os conflitos antes de
      aplicar, então a posição no mapa não muda o comportamento).
- [x] Confirmar que nenhuma alteração ocorre quando a validação encontra um
      conflito. *(exit code 2, árvore de arquivos inalterada)*
- [x] Reexecutar os instaladores e confirmar idempotência. *(segunda execução
      só reportou `OK`)*

  *(Lado Windows/PowerShell usa a mesma lógica de duas passagens, mas não foi
  executado ao vivo — `pwsh` indisponível neste ambiente.)*

**Arquivos prováveis:**

- `SamsungBook-Np550xda/Omarchy/omarchy.pl`
- `SamsungBook-Np550xda/Windows-11/win11.ps1`

**Dependências:** tarefa 1 para o fluxo de restore do Windows.

### 3. Corrigir a ativação do AincradHUD

Uma seção `[AincradHUD]` existente com `Active=0` ou `AlwaysOnTop=0` não é
reativada corretamente.

**Critérios de aceite:**

- [x] `Active` termina como `1`, exista ou não previamente na seção. (commit
      `a94e2cf`)
- [x] `AlwaysOnTop` termina como `1`, exista ou não previamente na seção.
- [x] Chaves de outras seções não são modificadas.
- [x] A execução repetida não duplica propriedades ou seções.

**Verificação:**

- [ ] Testar seção ausente.
- [ ] Testar seção existente com valores `0`.
- [ ] Testar seção existente sem uma ou ambas as propriedades.
- [ ] Testar idempotência com duas execuções consecutivas.

  *(Não executado: requer `pwsh`, indisponível neste ambiente. Lógica revisada
  manualmente linha a linha para os quatro casos.)*

**Arquivos prováveis:**

- `SamsungBook-Np550xda/Windows-11/win11.ps1`

**Dependências:** nenhuma.

### 4. Corrigir a ordem de execução de `win11.ps1 -All`

O tema é aplicado antes da instalação de Windows Terminal e Rainmeter. Em uma
máquina nova, partes do tema são puladas e não são repetidas depois.

**Critérios de aceite:**

- [x] `-All` instala aplicativos e módulos antes de aplicar configurações que
      dependem deles. (commit `36acf48`)
- [x] A execução de flags individuais mantém o comportamento atual.
- [x] Falha de `winget` ou `Install-Module` é detectada e impede uma mensagem
      final de sucesso enganosa. (`Install-Apps` verifica `winget list` antes
      de instalar e o exit code depois; `Install-Module` já propaga erro
      terminante com `$ErrorActionPreference = 'Stop'`)

**Verificação:**

- [ ] Conferir com `-All -DryRun` que a ordem é links, fontes, aplicativos,
      módulos e tema.
- [ ] Simular falha de instalação e confirmar código de saída diferente de
      zero.
- [ ] Executar novamente após uma instalação completa e confirmar
      idempotência.

  *(Não executado: requer `pwsh`, indisponível neste ambiente.)*

**Arquivos prováveis:**

- `SamsungBook-Np550xda/Windows-11/win11.ps1`
- `SamsungBook-Np550xda/Windows-11/README.md`

**Dependências:** tarefa 3 recomendada antes da verificação integrada do tema.

### 5. Fixar versões das dependências externas

Imagens Docker e alguns downloads usam referências mutáveis como `latest`.
Isso reduz a reprodutibilidade e permite mudanças upstream inesperadas.

**Critérios de aceite:**

- [x] Imagens de FrankMD, ai-memory e Pi-hole usam versão ou digest explícito.
      (commit `5168595`: `1.0.1`, `2.3.0`, `2026.07.2`)
- [x] O wrapper ai-memory usa uma release explícita (`v2.3.0`) e checksum
      conhecido no repositório (hardcoded em `ensure_wrapper()`, não mais
      baixado do mesmo alvo móvel).
- [x] JetBrainsMono Nerd Font usa uma versão explícita (`v3.5.1`).
- [x] O processo de atualização deliberada está documentado (Omarchy e
      Windows READMEs).

**Verificação:**

- [x] `docker compose config --quiet` passa.
- [x] As três tags novas resolvem para manifests reais (`docker manifest
      inspect`); `docker compose pull` completo não foi executado (baixaria
      várias imagens grandes sem necessidade para esta verificação).
- [ ] Checksums inválidos fazem os instaladores abortarem antes de instalar.
- [ ] O stack sobe e os healthchecks ficam saudáveis após a atualização.

  *(Os dois últimos itens exigem subir o stack completo com segredos reais;
  não executado nesta sessão.)*

**Arquivos prováveis:**

- `SamsungBook-Np550xda/Omarchy/docker/docker-compose.yml`
- `SamsungBook-Np550xda/Omarchy/scripts/docker-stack.pl`
- `SamsungBook-Np550xda/Windows-11/win11.ps1`
- READMEs relacionados

**Dependências:** nenhuma.

## Prioridade baixa

### 6. Sincronizar a documentação arquitetural

O documento ainda identifica um commit antigo e a descrição de `--apps` não
inclui todos os webapps atualmente provisionados.

**Critérios de aceite:**

- [x] A referência de data/commit representa o estado efetivamente analisado
      ou é substituída por uma descrição que não envelheça imediatamente.
      (commit `f869390`)
- [x] A documentação de `--apps` corresponde ao conteúdo de `ensure_apps()`
      (webapps de IA e remoção de HEY/Basecamp/1Password que faltavam).
- [x] As limitações removidas pelas tarefas anteriores deixam de aparecer como
      problemas ativos.
- [x] README e arquitetura concordam sobre ordem de instalação e restore.

**Verificação:**

- [x] Comparar cada flag documentada com o respectivo instalador.
- [x] Validar links Markdown e renderização dos diagramas Mermaid. (8/8
      diagramas renderizados com `@mermaid-js/mermaid-cli`; links resolvidos
      em um clone limpo do repositório)
- [x] Executar `git diff --check`.

**Arquivos prováveis:**

- `SamsungBook-Np550xda/docs/architecture.md`
- `SamsungBook-Np550xda/Omarchy/README.md`
- `SamsungBook-Np550xda/Windows-11/README.md`

**Dependências:** tarefas 1 a 5.

### 7. Decidir e registrar o escopo do repositório raiz

O `README.md` raiz e `Skill-Library/` estão presentes localmente, mas ainda não
são rastreados. O clone do commit publicado contém apenas
`SamsungBook-Np550xda/`.

**Critérios de aceite:**

- [x] Decidir se `Skill-Library/` pertence a este repositório, será um
      submódulo ou ficará em repositório separado. (decisão confirmada pelo
      usuário: rastrear neste repositório, sem submódulo; commit `eaaad08`)
- [x] Ajustar o README raiz para refletir a decisão.
- [x] Rastrear apenas os arquivos pretendidos, sem caches, artefatos ou
      segredos.

**Verificação:**

- [x] Clonar o repositório em um diretório temporário e confirmar que todos os
      links do README resolvem. (único "broken" encontrado é um texto de
      exemplo `[x reference](link)` dentro de `skills/diataxis/SKILL.md`,
      ilustrando sintaxe Markdown, não um link real)
- [x] Confirmar com `git status --short` que não restam arquivos pretendidos
      sem rastreamento.
- [x] Examinar o diff staged em busca de `.env`, chaves, tokens e credenciais.

**Arquivos prováveis:**

- `README.md`
- `Skill-Library/` ou configuração de submódulo
- `.gitignore`, se necessário

**Dependências:** decisão explícita sobre onde a biblioteca de skills deve ser
mantida.

## Checkpoints

### Depois das tarefas 1 e 2

- [ ] Backup e restore foram testados ponta a ponta em destinos temporários.
      *(feito para Omarchy/Perl; pendente para Windows/PowerShell — sem `pwsh`
      neste ambiente)*
- [x] Nenhum fluxo deixa alterações parciais após conflito de validação.
      *(comprovado ao vivo no lado Omarchy; garantido por construção no lado
      Windows, mesma lógica de duas passagens)*
- [ ] Revisão de segurança feita sobre remoções e sobrescritas de caminhos.
      *(não feita como passagem dedicada separada; a validação por hash antes
      de sobrescrever foi projetada com isso em mente, mas não houve revisão
      de segurança formal independente)*

### Depois das tarefas 3 a 5

- [ ] `-All` funciona em uma instalação Windows limpa e em uma já configurada.
      *(pendente — sem `pwsh`)*
- [ ] O stack Docker sobe com versões fixadas e healthchecks saudáveis.
      *(pendente — não subiu o stack completo com segredos reais)*
- [ ] Scripts Perl, Bash, Lua, PowerShell, JSON e Compose passam nas validações
      disponíveis. *(Perl: `perl -c` ok; Compose: `docker compose config` ok;
      PowerShell: sem validador disponível, só revisão manual; nenhum Bash/Lua/
      JSON foi alterado nesta rodada)*

### Conclusão

- [x] Documentação corresponde ao comportamento verificado.
- [x] Não há segredos no diff nem no conjunto de arquivos rastreados.
- [x] `git diff --check` passa.
- [x] Cada correção foi mantida em um commit atômico e revisável.
