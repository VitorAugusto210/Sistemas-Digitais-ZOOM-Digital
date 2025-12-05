# Zoom Digital: Módulo de Redimensionamento de Imagens com Seleção de Janela

## Sumário
* [1. Visão Geral do Projeto](#1-visão-geral-do-projeto)
* [2. Definição do Problema](#2-definição-do-problema)
* [3. Requisitos do Projeto](#3-requisitos-do-projeto)
    * [3.1. Requisitos Funcionais](#31-requisitos-funcionais)
    * [3.2. Requisitos Não Funcionais](#32-requisitos-não-funcionais)
* [4. Fundamentação Teórica](#4-fundamentação-teórica)
    * [4.1. Zoom In e Zoom Out](#41-zoom-in-e-zoom-out)
    * [4.2. Overlay de Hardware](#42-overlay-de-hardware)
* [5. Ambiente de Desenvolvimento](#5-ambiente-de-desenvolvimento)
    * [5.1. Software Utilizado](#51-software-utilizado)
    * [5.2. Hardware Utilizado](#52-hardware-utilizado)
* [6. Manual do Usuário](#6-manual-do-usuário)
    * [6.1. Instalação e Configuração](#61-instalação-e-configuração)
    * [6.2. Comandos de Operação](#62-comandos-de-operação)
* [7. Descrição da Solução](#7-descrição-da-solução)
    * [7.1. `soc_system.qsys` (Sistema HPS e Barramento)](#71-soc_systemqsys-sistema-hps-e-barramento)
    * [7.2. `ghrd_top.v` (Arquivo Top-Level)](#72-ghrd_topv-arquivo-top-level)
    * [7.3. `main.v` (Módulo do Coprocessador)](#73-mainv-módulo-do-coprocessador)
    * [7.4. `mem1.v` (Módulo de Memória)](#74-mem1v-módulo-de-memória)
    * [7.5. `api_fpga.s` (A API de Hardware em Assembly)](#75-api_fpgas-a-api-de-hardware-em-assembly)
    * [7.6. `constantes.h` (O Dicionário do Projeto)](#76-constantesh-o-dicionário-do-projeto)
    * [7.7. `menu.c` (A Aplicação Principal)](#77-menuc-a-aplicação-principal)
* [8. Testes e Validação](#8-testes-e-validação)
    * [8.1. Interação com Mouse](#81-interação-com-mouse)
    * [8.2. Definição de Janela](#82-definição-de-janela)
    * [8.3. Zoom Localizado](#83-zoom-localizado)
* [9. Análise dos Resultados](#9-análise-dos-resultados)

---

## 1. Visão Geral do Projeto

Este projeto foi desenvolvido como parte da avaliação da disciplina de Sistemas Digitais (TEC499) do curso de Engenharia de Computação da Universidade Estadual de Feira de Santana (UEFS). O objetivo principal é projetar um módulo embarcado para redimensionamento de imagens em tempo real, permitindo a seleção de regiões de interesse via mouse.

O sistema é controlado pelo processador HPS (ARM), que executa uma aplicação multithread em C. Esta aplicação gerencia a leitura de um mouse USB e comandos via terminal, comunicando-se com um coprocessador gráfico na FPGA para realizar o processamento de vídeo e a sobreposição visual (overlay) da interface.

A base do código em Verilog foi adaptada do repositório: <https://github.com/DestinyWolf/Problema-SD-2025-2> com devida permissão do Autor.

## 2. Definição do Problema

O foco deste estágio é a evolução da interface e a sincronização entre processos de software e hardware.

O objetivo é projetar um sistema onde o usuário possa utilizar um mouse para desenhar uma janela sobre a imagem original. O coprocessador deve então aplicar os algoritmos de zoom apenas dentro dessa janela delimitada, mantendo o restante da imagem original como fundo (background).

## 3. Requisitos do Projeto

### 3.1. Requisitos Funcionais

* **RF01:** A aplicação deve fornecer uma interface de texto que permita carregar arquivo bitmap e selecionar algoritmo de zoom.
* **RF02:** Deve ser possível usar o mouse para selecionar uma região da tela (janela) para ampliação (zoom in).
* **RF03:** A janela ampliada deve ser desenhada sobre a imagem original (Overlay).
* **RF04:** A posição (x, y) do mouse deve ser visualizada em tempo real por meio da interface de texto.
* **RF05:** O mouse será usado para definir dois cantos opostos da janela de ampliação, sendo cada canto selecionado ao pressionar um botão do mouse.
* **RF06:** Na janela definida, devem ser permitidas operações de zoom in e zoom out. O limite para o zoom out deve ser a resolução da imagem original.
* **RF07:** A tecla **+ (mais)** deve realizar a operação de zoom in na janela ativa.
* **RF08:** A tecla **- (menos)** deve realizar a operação de zoom out na janela ativa.

### 3.2. Requisitos Não Funcionais

* **RNF01:** O código da aplicação deve ser escrito em linguagem C.
* **RNF02:** O driver do processador (biblioteca) deve ser ligado ao código da aplicação principal.
* **RNF03:** Um arquivo header deve servir para armazenar os protótipos dos métodos da API da controladora.

## 4. Fundamentação Teórica

Esta seção detalha a teoria por trás das operações de redimensionamento de imagem implementadas no projeto.

### 4.1. Zoom In (Aproximação)

Aproximar uma imagem significa criar novos pixels onde antes não existia informação para preencher uma área de exibição maior.

* **Vizinho Mais Próximo (Nearest Neighbor) [RF03]:**
    * **Teoria:** É o método de interpolação mais simples. Para cada pixel na imagem de destino, o algoritmo seleciona o valor do pixel mais próximo correspondente na imagem original.
    * **Implementação:** No hardware, isso é realizado através do cálculo de endereços de memória. Para um zoom de 2x, o endereço de leitura é incrementado na metade da velocidade do endereço de escrita (ou através de deslocamento de bits), resultando na repetição de cada pixel original.
    * **Resultado Visual:** Produz uma imagem nítida, mas com efeito "pixelado" ou serrilhado evidente nas bordas.

* **Replicação de Pixel [RF04]:**
    * **Teoria:** Foca em duplicar a informação existente. Cada pixel original $(x, y)$ é transformado num bloco de pixels (ex: $2 \times 2$) na imagem de destino.
    * **Nota:** Para fatores de zoom inteiros (2x, 4x, 8x), o resultado matemático e visual deste método é idêntico ao do Vizinho Mais Próximo.

### 4.2. Zoom Out (Redução via Regressão)

Tradicionalmente, reduzir uma imagem envolve descartar informações (Decimação) ou combinar pixels (Média) para caber numa resolução menor. No entanto, neste projeto, adotou-se uma abordagem não destrutiva para a navegação entre níveis de zoom.

* **Regressão de Nível (Level Regression):**
    * **Teoria:** Em vez de processar a imagem que já está na tela (que já sofreu zoom/interpolação) aplicando um filtro de redução sobre ela, o sistema "volta".
    * **Funcionamento:** Quando o utilizador solicita um Zoom Out (ex: de 4x para 2x), o controlador decrementa o fator de escala global e solicita ao coprocessador que gere a imagem novamente a partir da **Memória Original (Source)**.
    * **Vantagem:** Isso evita a degradação cumulativa da imagem (artefatos de reamostragem) que ocorreria ao aplicar múltiplos filtros em cascata. Garante que a visualização de um nível de zoom (ex: 2x) seja sempre idêntica e perfeita, independentemente se o utilizador chegou a esse nível vindo de 1x (Zoom In) ou de 4x (Zoom Out).

### 4.3. Overlay de Hardware

Para desenhar o cursor e a janela sem corromper a memória da imagem, utiliza-se a técnica de Overlay. O hardware verifica a posição atual de varredura VGA (`pixel_x`, `pixel_y`) em tempo real:
1.  Se a posição coincide com o cursor do mouse -> Envia.
2.  Se a posição está dentro da janela ativa -> Lê da Memória de Processamento (Zoom).
3.  Caso contrário -> Lê da Memória de Fundo (Imagem Original).

## 5. Ambiente de Desenvolvimento

### 5.1. Software Utilizado

| Software | Versão | Descrição |
| :--- | :--- | :--- |
| Quartus Prime | 23.1.0 | Ferramenta de desenvolvimento para FPGAs Intel. |
| GNU/Linux Shell (bash) | (N/A)| Interface de linha de comandos (terminal) acedida via SSH. |

### 5.2. Hardware Utilizado

| Componente | Especificação |
| :--- | :--- |
| Kit de Desenvolvimento | Terasic DE1-SoC |
| Monitor | Monitor com entrada VGA. |
| Computador | Para compilação do projeto e controle do Zoom In e Zoom Out |
| Mouse | Para movimentação do Cursor e seleção de Janela |

## 6. Manual do Usuário

### 6.1. Instalação e Configuração

1.  **Clonar o Repositório:**
    ```bash
    git clone [https://github.com/VitorAugusto210/Sistemas-Digitais-ZOOM-Digital.git](https://github.com/VitorAugusto210/Sistemas-Digitais-ZOOM-Digital.git)
    cd <NOME_DO_SEU_REPOSITORIO>
    ```
2.  **Configuração do Quartus Prime:**
    * Abra o Quartus Prime.
    * Abra o arquivo de projeto `.qpf` (localizado na pasta `Coprocessador`).
3.  **Compilação (Hardware):**
    * Com o Quartus aberto, clique no botão de Start Compilation.
        ![botao_compilar](imgs/start_compilation.png)
    * Isso irá gerar o arquivo de programação (`.sof`).
4.  **Programação da FPGA:**
    * Conecte a placa DE1-SoC ao computador.
    * Abra o "Programmer" no Quartus Prime.
        ![programmer](imgs/programmer.png)
    * Selecione o arquivo `.sof` gerado e programe a placa.
    * Clique em "Start" e as instruções serão repassadas a placa.

5.  **Conectando e Compilando o Software no HPS:**
    * Abra um terminal e conecte-se à placa via SSH:
        ```bash
        ssh aluno@172.65.213.<Digitos finais da Placa utilizada>
        # Forneça a senha da máquina assim que solicitada
        ```
    * Transfira os arquivos de software (`menu.c`, `constantes.h`, `api_fpga.s`, `Makefile`) do seu computador para a placa usando `scp`.
    * Transfira a imagem bitmap e o Makefile para a placa:
        ```bash
        # Em um terminal no SEU computador
        scp /<Diretorio da imagem em bitmap> aluno@172.65.213.<...>:~/
        scp /<Diretorio do Makefile> aluno@172.65.213.<...>:~/
        ```
    * De volta ao terminal SSH na placa, compile o software:
        ```bash
        make # Makefile que faz toda compilação
        ```
    * Execute o programa:
        ```bash
        sudo ./app # Executável gerado pelo Makefile
        ```

### 6.2. Comandos de Operação

Após executar o programa (`sudo ./app`), os seguintes comandos estão disponíveis:

| Entrada | Ação |
| :--- | :--- |
| **Mouse (Movimento)** | Move o cursor vermelho na tela. |
| **Mouse (Clique Esq.)** | **1º Clique:** Define o canto superior esquerdo da janela.<br>**2º Clique:** Define o canto inferior direito e **ativa** a janela. |
| **Mouse (Clique Dir.)** | Reseta a janela, voltando ao modo de tela cheia sem zoom. |
| **Teclado '+' / 'i'** | Aplica Zoom IN dentro da janela ativa (ou na tela toda). |
| **Teclado '-' / 'o'** | Aplica Zoom OUT dentro da janela ativa. |
| **Teclado 'n' / 'm'** | Alterna os algoritmos de processamento (In/Out). |
| **Teclado 'l'** | Carrega uma nova imagem BMP. |
| **Teclado 'r'** | Reseta a imagem e remove a janela. |
| **Teclado 'q'** | Encerra o programa. |

## 7. Descrição da Solução

A arquitetura do projeto é um **sistema híbrido Hardware-Software**. O diagrama abaixo ilustra o fluxo de dados completo, desde a captura dos eventos do mouse no Linux até a renderização dos pixels no monitor via FPGA.

![Diagrama de Blocos da Arquitetura](imgs/diagrama.png)
### 7.1. `soc_system.qsys` (Sistema HPS e Barramento)
...

### 7.1. `soc_system.qsys` (Sistema HPS e Barramento)

Criado no Platform Designer (Qsys), ele define o sistema de processamento principal e sua conexão com a lógica da FPGA.

* **Propósito:** Configurar o processador **ARM (HPS)** e criar a ponte de comunicação (barramento Avalon) entre o software (executando no HPS) e o hardware (Coprocessador na FPGA).
* **Interface de Comunicação (PIOs):** `pio_instruct`, `pio_enable`, `pio_dataout`, `pio_flags`.

### 7.2. `ghrd_top.v` (Arquivo Top-Level)

Este é o arquivo Verilog de nível mais alto do projeto. Ele representa o design completo da FPGA, conectando os blocos lógicos aos pinos físicos da placa.

* **Propósito:** Instanciar e "conectar" o sistema HPS (`soc_system`) e o nosso coprocessador (`main.v`) um ao outro e aos pinos externos da placa DE1-SoC.

### 7.3. `main.v` (Módulo do Coprocessador)

Este é o coração da lógica de FPGA customizada. Nesta etapa, o módulo evoluiu de um processador de "tela cheia" para um gerenciador de janelas e sobreposições (overlays).

* **Propósito:** Implementar a Máquina de Estados Finitos (FSM), o *datapath* para os algoritmos de zoom e o pipeline de vídeo com suporte a cursor e janelas.

* **Componentes Chave:**
    * **PLL (`pll0`):** Gera os clocks `clk_100` (Lógica) e `clk_25_vga` (VGA).
    * **Registradores de Interface Visual (Novo):** Foram adicionados registradores (`cursor_x/y`, `win_start_x/y`, `win_end_x/y`, `window_active`) para armazenar o estado da interface gráfica (mouse e janela), permitindo que o hardware desenhe esses elementos independentemente da memória da imagem.
    * **Pipeline VGA com Overlay (Novo):** O controlador de vídeo foi reescrito. Um multiplexador no bloco `always` decide, pixel a pixel, qual cor enviar para o monitor:
        1.  **Camada 1 (Cursor):** Se o pixel atual pertence à cruz do mouse, exibe **Vermelho**.
        2.  **Camada 2 (Janela):** Se está dentro da janela ativa, exibe o conteúdo da **Memória de Zoom** (`mem2`).
        3.  **Camada 3 (Fundo):** Caso contrário, exibe o conteúdo da **Memória Original** (`mem1`).
    * **Memórias (`mem1`):** O sistema utiliza três instâncias de memória RAM:
        1. `memory1`: Imagem original (fundo).
        2. `memory2`: Imagem processada (janela).
        3. `memory3`: Buffer de trabalho.
    * **Máquina de Estados Finitos (FSM):**
        * **Estado `IDLE` (Configuração):** Detecta instruções especiais (Opcode `REFRESH` + `SEL_MEM`=1) para atualizar as coordenadas da janela e do mouse instantaneamente via hardware, usando bits do endereço como sub-comandos.
        * **Algoritmos com Clipping:** Os algoritmos (`PR_ALG`, `NHI_ALG`, etc.) agora restringem seus laços de repetição (`loops`) apenas à área definida por `win_start` e `win_end`, preservando o resto da imagem.
        * **Shift Dinâmico:** Implementada lógica para calcular endereços de memória de origem com precisão de 32 bits, garantindo que o zoom permaneça centralizado na janela em níveis 2x, 4x e 8x.

### 7.4. `mem1.v` (Módulo de Memória)

Este arquivo é um wrapper para um bloco de memória `altsyncram`, gerado pelo MegaFunction Wizard.

* **Propósito:** Definir um bloco de memória RAM síncrona de porta dupla (Dual-Port). Permite que a FSM escreva na memória (Porta A) ao mesmo tempo em que o controlador VGA lê dela (Porta B).

### 7.5. `api_fpga.s` (Driver Assembly)

Este arquivo atua como o "driver" de baixo nível do coprocessador, escrito em Assembly ARM. Ele abstrai a comunicação direta com os endereços físicos dos PIOs, fornecendo funções que podem ser chamadas pelo código C.

* **Propósito:** Gerenciar a escrita e leitura nos registradores de controle e memória da FPGA.
* **Funções Exportadas:**
    * **`setup_memory_map()`:** Inicializa o sistema, mapeando os endereços físicos da ponte HPS-FPGA para a memória virtual do Linux.
    * **`cleanup_memory_map()`:** Libera os recursos alocados.
    * **`coproc_write_pixel(address, value)`:** Escreve um valor de pixel na memória da FPGA.
    * **`coproc_read_pixel(address, sel_mem)`:** Lê o valor de um pixel da memória da FPGA.
    * **`coproc_apply_zoom(algorithm_code)`:** Envia comando de zoom (tela cheia).
    * **`coproc_reset_image()`:** Envia comando de RESET para restaurar a imagem original.
    * **`coproc_wait_done()`:** Bloqueia a execução até que a FPGA sinalize o fim da operação.
    * **`coproc_apply_zoom_with_offset(algorithm, x, y)`:** Envia comando de zoom com deslocamento para centralização.
    * **`coproc_update_mouse(x, y)`:** Atualiza a posição do cursor no hardware.
    * **`coproc_set_window_start/end(x, y)`:** Define os cantos da janela de zoom.
    * **`coproc_set_window_active(state)`:** Ativa/Desativa o overlay da janela.

### 7.6. `constantes.h` (O Dicionário do Projeto)

Este é um ficheiro de cabeçalho em C que centraliza endereços e códigos.

* **Conteúdo:**
    * Endereços Base da Ponte e Offsets dos PIOs.
    * Opcodes de Instrução (`OP_LOAD`, `OP_STORE`, `OP_NHI_ALG`, etc.).
    * **Sub-comandos de Configuração:** Novos códigos para controle de janela (`SUBCMD_UPDATE_MOUSE`, `SUBCMD_SET_WIN_START`, etc.).
    * Máscaras de Flags.

### 7.7. `menu.c` (A Aplicação Principal)

Programa principal em C que roda no Linux do HPS, atuando como orquestrador do sistema.

* **Propósito:** Interface do usuário e lógica de controle de alto nível.
* **Novidades (Etapa 3):**
    * **Arquitetura Multithread (`pthread`):** Utiliza duas threads: uma para gerir o menu/teclado e outra (`mouse_thread_func`) dedicada à leitura contínua do rato (`/dev/input/mice`), garantindo fluidez.
    * **Controlo de Concorrência (Mutex):** Usa `pthread_mutex_t` para proteger o acesso aos registradores da FPGA, evitando conflitos de escrita.
    * **Máquina de Estados de Janela:** Gere a lógica de cliques (1º clique -> 2º clique -> janela ativa).
    * **Cálculo de Offset Matemático:** Calcula o ponto de origem da memória para garantir que o zoom seja aplicado no centro da janela definida, compensando o fator de escala.

## 8. Testes e Validação
**Vizinho Mais Próximo**

![vizinho-mais-proximo](imgs/vizinho_proximo.gif)

**Replicação de Pixel**

![vizinho-mais-proximo](imgs/replicacao-pixel.gif)

### 8.1. Interação com Mouse
Validou-se que o cursor gerado pela FPGA segue o movimento físico do mouse sem atrasos perceptíveis, confirmando a eficiência da leitura via thread separada.

### 8.2. Definição de Janela
O teste consistiu em clicar em dois pontos distintos da tela (Foi optado pela equipe a seleção apenas de pontos da **Esquerda** para a **Direita**). Observou-se que, após o segundo clique, a região interna passa a ser gerenciada pela memória de zoom, validando a lógica de overlay e os registradores de janela.

### 8.3. Zoom Localizado
Ao aplicar zoom (+) com uma janela ativa, apenas o conteúdo interno à borda foi ampliado (Limite de 8x no zoom). O centro da janela foi preservado graças ao cálculo de offset implementado no software e à lógica de shift dinâmico no hardware.

### 8.4. Zoom Out
Ao aplicar zoom Out (-) com uma janela ativa, apenas o conteúdo interno à borda foi reduzido (limitada ao tamanho original da imagem). O centro da janela foi preservado graças ao cálculo de offset implementado no software e à lógica de shift dinâmico no hardware.

## 9. Análise dos Resultados

A implementação foi bem-sucedida. A transição de um controle via teclado para um sistema baseado em mouse adicionou uma complexidade, exigindo o uso de conceitos de sistemas operacionais como Threads e Mutex e lógica de Overlay.

Um ponto crítico resolvido foi a **sincronização de estado**: ao criar uma nova janela, o software força um reset na FPGA (`coproc_reset_image`) antes de ativar a nova região. Isso garante que tanto o contador lógico de zoom do software quanto o estado da FSM do hardware comecem sincronizados em 1x, prevenindo desalinhamentos visuais.