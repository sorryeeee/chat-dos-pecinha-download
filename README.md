# Chat dos Pecinha — Download

Repositório público **somente para instalação e atualização**.

O código-fonte do aplicativo fica em um repositório privado separado.

## Hotfix do instalador — validação da Voice Call

- remove a checagem frágil pelo texto antigo `Sala de voz da Squad`;
- valida os IDs estruturais reais da Voice Call no HTML;
- valida `voice-join`, `voice-leave` e `joinVoiceCall` no renderer;
- valida também o SHA de `desktop/package.json` e confirma a versão instalada.
- não altera a versão do app: continua `1.3.25.6.8.6.10-online-1`.


## Instalar / atualizar

```powershell
irm "https://raw.githubusercontent.com/sorryeeee/chat-dos-pecinha-download/main/bootstrap.ps1?x=$(Get-Random)" | iex
```

Versão atual: `1.3.25.6.8.6.10-online-1`

## Conteúdo deste repositório

- `bootstrap.ps1`
- `install.ps1`
- `release/latest.zip`
- `release/latest.sha256`
- pacote versionado e SHA-256

Não coloque `src/`, `payload/`, ferramentas de desenvolvimento ou
arquivos de estado/autenticação neste repositório.


## 1.3.25.6.8.6.2-online-1 — logo oficial

A imagem do mascote preto com detalhes dourados agora é a identidade oficial no header, login, janela, tray, taskbar e atalhos.


## 1.3.25.6.8.6.3-online-1 — Logo asset hotfix

Corrige o updater para instalar `desktop/brand-logo.png`.
A logo oficial agora é copiada tanto em instalação nova quanto em atualização.


## 1.3.25.6.8.6.4-online-1 — Logo CSP final fix

A logo visível do header/login/rodapé agora é embutida como `data:` no HTML.
Isso elimina dependência de resolução `file://` e evita bloqueio por CSP.
Tray, janela e atalho continuam usando os assets PNG/ICO locais.


## Atualização automática

Versão obrigatória: `1.3.25.6.8.6.10-online-1`. O HOST consulta `release/version.json` e avisa clientes em tempo real.


## 1.3.25.6.8.6.6-online-1

Metadados de versão dos demais clientes são exibidos somente para o admin.
O mecanismo de atualização automática continua igual para todos.


## 1.3.25.6.8.6.7-online-1

- corrige o updater obrigatório quando o `version.json` do Git estiver atrasado;
- o HOST nunca mais permite que o Git reduza a versão/protocolo mínimos;
- a versão instalada no HOST é sempre um piso de compatibilidade;
- clientes antigos recebem `version-policy` e `force-update`;
- o manifesto é consultado a cada nova conexão e novamente a cada 10 segundos;
- cliente incompatível é bloqueado/desconectado após 2,5 segundos;
- `sorrye` continua sendo o único perfil que vê as versões dos demais clientes.


## 1.3.25.6.8.6.10-online-1

- corrige o botão de atualização automática que em alguns PCs apenas fechava o app;
- `bootstrap.ps1` agora pede elevação imediatamente e deixa download/instalação no processo elevado independente;
- o `main.js` novo aguarda a criação real do instalador elevado antes de fechar o Electron;
- cancelamento do UAC ou falha ao iniciar mantém o app aberto e exibe o erro.


## Cloud Ready

A partir desta versão o cliente aceita `https://`/`wss://` e pode migrar para VPS sem Tailscale. `switch-to-cloud.ps1` troca o `config.json` para a URL Cloud e desativa o HOST local quando necessário.
