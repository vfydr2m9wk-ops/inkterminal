# InkTerminal

Um terminal Linux de verdade que roda inteiro no navegador, pensado para o iPad (Safari) e para ser usado dentro do [InkDOS](https://github.com/vfydr2m9wk-ops/InkDOS).

- Kernel Linux 6.6 (i386) com BusyBox, emulado pelo [v86](https://github.com/copy/v86) em WebAssembly.
- Não usa servidor: tudo roda localmente na aba.
- Liga em poucos segundos (a imagem do sistema tem só 3 MB).
- Botão **Salvar** guarda a máquina inteira (arquivos, comandos abertos) no navegador. Na próxima visita ela volta do mesmo ponto. **Reiniciar** apaga e começa do zero.
- Barra de teclas extras para o teclado do iPad: Esc, Tab, Ctrl, setas, `|`, `/`, `-`, `~`, Ctrl+C.

## Usar

Abra a página publicada no GitHub Pages. No iPad, toque em Compartilhar → "Adicionar à Tela de Início" para abrir como app.

Parâmetros de URL:

| Parâmetro | Efeito |
|---|---|
| `?embed=1` | Esconde a barra do topo (para usar dentro de um iframe no InkDOS) |
| `?fresh=1` | Ignora o estado salvo e liga do zero |
| `?font=18` | Tamanho da fonte |

## Usar dentro do InkDOS

```html
<iframe src="https://vfydr2m9wk-ops.github.io/inkterminal/?embed=1" style="width:100%;height:100%;border:0"></iframe>
```

## Limitações

- É emulação, então é bem mais lento que um computador de verdade.
- Sem internet dentro do Linux por enquanto (precisaria de um relay de WebSocket).
- Só tem os comandos do BusyBox (sem `apt`/`apk`).

## Estrutura

| Caminho | O que é |
|---|---|
| `index.html`, `app.js`, `style.css` | A página do terminal |
| `vendor/v86/` | Emulador v86 0.5.471 (licença BSD-2) |
| `vendor/xterm/` | xterm.js 6.0.0 + addon-fit (licença MIT) |
| `bios/` | SeaBIOS e VGA BIOS (LGPL-3) |
| `images/inkterminal-bzImage.bin` | Kernel Linux 6.6 com o BusyBox embutido (GPL-2) |
| `build/` | Script e configurações para recompilar a imagem |

## Recompilar a imagem do Linux

Precisa de uma máquina Linux (ou um runner de CI) com `gcc gcc-multilib make flex bison bc cpio libelf-dev git`:

```sh
./build/build.sh
```

O kernel vem de `torvalds/linux` na tag `v6.6` e o BusyBox de `mirror/busybox` no commit `371fe9f`, ambos sem modificações. A configuração usada está em `build/`.
