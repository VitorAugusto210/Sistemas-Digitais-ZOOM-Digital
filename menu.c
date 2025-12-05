#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <termios.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <pthread.h> // Essencial para Mutex
#include <stdbool.h>

#include "constantes.h"

// =================================================================
// Protótipos das Funções da API (api_fpga.s)
// =================================================================
extern int setup_memory_map(void); // Configura o mapeamento de memória
extern void cleanup_memory_map(void); // Limpa o mapeamento de memória
extern void coproc_write_pixel(uint32_t address, uint8_t value); // Escreve um pixel na memória da FPGA
extern uint8_t coproc_read_pixel(uint32_t address, uint32_t sel_mem); // Lê um pixel da memória da FPGA
extern void coproc_apply_zoom(uint32_t algorithm_code); // Aplica o zoom com o algoritmo especificado
extern void coproc_reset_image(void); // Reseta a imagem na FPGA
extern void coproc_wait_done(void); // Espera até a FPGA sinalizar que terminou o processamento

extern void coproc_apply_zoom_with_offset(uint32_t algorithm_code, uint32_t x_offset, uint32_t y_offset);

extern void coproc_update_mouse(uint32_t x, uint32_t y); // Atualiza a posição do mouse na FPGA
extern void coproc_set_window_start(uint32_t x, uint32_t y); // Define o canto superior esquerdo da janela
extern void coproc_set_window_end(uint32_t x, uint32_t y); // Define o canto inferior direito da janela
extern void coproc_set_window_active(uint32_t state); // Ativa/Desativa a janela de zoom na FPGA

// =================================================================
// Variáveis Globais
// =================================================================
#define IMG_WIDTH  320
#define IMG_HEIGHT 240

// Mutex para proteger o acesso à FPGA entre Thread e Main
pthread_mutex_t fpga_mutex = PTHREAD_MUTEX_INITIALIZER;

volatile int g_mouse_x = IMG_WIDTH / 2;
volatile int g_mouse_y = IMG_HEIGHT / 2;
volatile bool g_mouse_left_click = false;
volatile bool g_mouse_right_click = false;
volatile bool g_program_running = true;

// Rastreio do nível de zoom lógico (1, 2, 4, 8)
int g_current_zoom_factor = 1;
// Rastreio do estado da janela de zoom
typedef enum { WIN_STATE_IDLE, WIN_STATE_WAIT_END, WIN_STATE_ACTIVE } WindowState;
WindowState g_win_state = WIN_STATE_IDLE; // Estado inicial: sem janela
uint32_t g_win_x1 = 0, g_win_y1 = 0; // Canto superior esquerdo da janela
uint32_t g_win_x2 = 0, g_win_y2 = 0; // Canto inferior direito da janela

// Modos de Zoom
typedef enum { ZOOM_OUT_NEAREST_NEIGHBOR, ZOOM_OUT_BLOCK_AVERAGE } ZoomOutMode;
typedef enum { ZOOM_IN_PIXEL_REPETITION, ZOOM_IN_NEAREST_NEIGHBOR } ZoomInMode;
ZoomOutMode current_zoom_out_mode = ZOOM_OUT_BLOCK_AVERAGE;
ZoomInMode  current_zoom_in_mode  = ZOOM_IN_PIXEL_REPETITION;

// =================================================================
// Estruturas BMP
// =================================================================
#pragma pack(1)
typedef struct {
    uint16_t bfType; uint32_t bfSize; uint16_t bfReserved1; uint16_t bfReserved2; uint32_t bfOffBits;
} BITMAPFILEHEADER;
typedef struct {
    uint32_t biSize; int32_t biWidth; int32_t biHeight; uint16_t biPlanes; uint16_t biBitCount;
    uint32_t biCompression; uint32_t biSizeImage; int32_t biXPelsPerMeter; int32_t biYPelsPerMeter;
    uint32_t biClrUsed; uint32_t biClrImportant;
} BITMAPINFOHEADER;
#pragma pack()

// =================================================================
// Thread do Mouse
// =================================================================
void *mouse_thread_func(void *arg) {
    int fd = open("/dev/input/mice", O_RDONLY);
    if (fd == -1) { printf("Erro Mouse\n"); return NULL; }
    signed char data[3];

    while (g_program_running) {
        if (read(fd, data, 3) > 0) {
            int dx = data[1]; int dy = -data[2];
            int left_btn = data[0] & 0x1; int right_btn = data[0] & 0x2;

            g_mouse_x += dx; g_mouse_y += dy;
            if (g_mouse_x < 0) g_mouse_x = 0; if (g_mouse_x >= IMG_WIDTH) g_mouse_x = IMG_WIDTH - 1;
            if (g_mouse_y < 0) g_mouse_y = 0; if (g_mouse_y >= IMG_HEIGHT) g_mouse_y = IMG_HEIGHT - 1;

            pthread_mutex_lock(&fpga_mutex);
            coproc_update_mouse(g_mouse_x, g_mouse_y);
            pthread_mutex_unlock(&fpga_mutex);

            if (left_btn && !g_mouse_left_click) {
                g_mouse_left_click = true;
                if (g_win_state == WIN_STATE_IDLE) {
                    g_win_x1 = g_mouse_x; g_win_y1 = g_mouse_y;
                    
                    pthread_mutex_lock(&fpga_mutex);
                    coproc_set_window_start(g_win_x1, g_win_y1);
                    pthread_mutex_unlock(&fpga_mutex);
                    
                    g_win_state = WIN_STATE_WAIT_END;
                } else if (g_win_state == WIN_STATE_WAIT_END) {
                    if (g_mouse_x > g_win_x1 && g_mouse_y > g_win_y1) {
                        g_win_x2 = g_mouse_x; g_win_y2 = g_mouse_y;
                        
                        pthread_mutex_lock(&fpga_mutex);
                        
                        coproc_reset_image();
                        coproc_wait_done();
                        
                        coproc_set_window_start(g_win_x1, g_win_y1);
                        coproc_set_window_end(g_win_x2, g_win_y2);
                        coproc_set_window_active(1);
                        
                        pthread_mutex_unlock(&fpga_mutex);
                        
                        g_current_zoom_factor = 1; 
                        g_win_state = WIN_STATE_ACTIVE;
                    }
                }
            } else if (!left_btn) g_mouse_left_click = false;

            if (right_btn && !g_mouse_right_click) {
                g_mouse_right_click = true;
                pthread_mutex_lock(&fpga_mutex);
                
                coproc_set_window_active(0);
                coproc_reset_image();
                coproc_wait_done();
                
                pthread_mutex_unlock(&fpga_mutex);
                
                g_current_zoom_factor = 1;
                g_win_state = WIN_STATE_IDLE;
            } else if (!right_btn) g_mouse_right_click = false;
        }
    }
    close(fd); return NULL;
}

int load_bmp_image(char *filename) {
    FILE *file = fopen(filename, "rb");
    if (!file) { perror("Erro Arquivo"); return -1; }
    
    BITMAPFILEHEADER h1; BITMAPINFOHEADER h2;
    fread(&h1, sizeof(h1), 1, file); fread(&h2, sizeof(h2), 1, file);
    fseek(file, h1.bfOffBits, SEEK_SET);
    int w = h2.biWidth; int h = h2.biHeight;
    int padding = (4 - (w * 1) % 4) % 4;

    printf("Carregando %s... ", filename);
    pthread_mutex_lock(&fpga_mutex);
    
    for (int y = h - 1; y >= 0; y--) { 
        for (int x = 0; x < w; x++) { 
            uint8_t p;
            if (fread(&p, 1, 1, file) < 1) p = 0; 
            uint32_t addr = (uint32_t)(y * w + x);
            if (addr < 131072) coproc_write_pixel(addr, p);
        }
        fseek(file, padding, SEEK_CUR);
    }
    pthread_mutex_unlock(&fpga_mutex);
    printf("OK.\n");
    fclose(file); return 0;
}

static struct termios old_t, new_t;
void set_terminal_mode() {
    tcgetattr(STDIN_FILENO, &old_t); new_t = old_t;
    new_t.c_lflag &= ~(ICANON | ECHO); tcsetattr(STDIN_FILENO, TCSANOW, &new_t);
}
void restore_terminal_mode() { tcsetattr(STDIN_FILENO, TCSANOW, &old_t); }

void print_status_bar() {
    printf("\r\033[K[Mouse: %03d, %03d] Win: %s | Zoom: %dx | Mode: %s/%s", 
        g_mouse_x, g_mouse_y,
        (g_win_state == WIN_STATE_ACTIVE) ? "ATIVO" : (g_win_state == WIN_STATE_WAIT_END) ? "DEF..." : "OFF",
        g_current_zoom_factor,
        current_zoom_in_mode ? "Near" : "P.Rep", current_zoom_out_mode ? "Avg" : "Near");
    fflush(stdout);
}

void print_menu() {
    printf("\n\n");
    printf("==========================================================\n");
    printf("    SISTEMA DE PROCESSAMENTO DE IMAGEM FPGA - DE1-SoC      \n");
    printf("==========================================================\n");
    printf(" CONTROLES DO MOUSE:\n");
    printf(" [Clique Esq.] : Definir janela de Zoom (1o: Inicio, 2o: Fim).\n");
    printf(" [Clique Dir.] : Resetar janela e voltar ao modo tela cheia.\n");
    printf("\n CONTROLES DO TECLADO:\n");
    printf(" [+] ou [I]    : Aplicar Zoom IN (Aumentar).\n");
    printf(" [-] ou [O]    : Aplicar Zoom OUT (Diminuir).\n");
    printf(" [N]           : Alternar Algoritmo de Zoom IN (Vizinho/Pixel Rep).\n");
    printf(" [M]           : Alternar Algoritmo de Zoom OUT (Media/Vizinho).\n");
    printf("\n SISTEMA:\n");
    printf(" [L]           : Carregar nova imagem BMP do disco.\n");
    printf(" [R]           : Resetar tudo (Imagem e Zoom).\n");
    printf(" [H]           : Mostrar este menu de ajuda.\n");
    printf(" [Q]           : Sair do programa.\n");
    printf("==========================================================\n");
    printf("\n");
}

void handle_zoom(int dir) {
    uint32_t algo;
    
    if (dir > 0) { 
        if (g_current_zoom_factor >= 8) {
            printf("\n[Aviso] Zoom maximo (8x) atingido.\n");
            return;
        }
        g_current_zoom_factor *= 2;
        algo = (current_zoom_in_mode == ZOOM_IN_PIXEL_REPETITION) ? OP_PR_ALG : OP_NHI_ALG;
    } else { 
        if (g_current_zoom_factor <= 1) {
            printf("\n[Aviso] Zoom minimo (1x) atingido.\n");
            return;
        }
        g_current_zoom_factor /= 2;
        algo = (current_zoom_out_mode == ZOOM_OUT_BLOCK_AVERAGE) ? OP_BA_ALG : OP_NH_ALG;
    }

    uint32_t offset_x = 0;
    uint32_t offset_y = 0;

    if (g_win_state == WIN_STATE_ACTIVE) {
        uint32_t width = g_win_x2 - g_win_x1;
        uint32_t height = g_win_y2 - g_win_y1;
        
        offset_x = g_win_x1 + (width * (g_current_zoom_factor - 1)) / (2 * g_current_zoom_factor);
        offset_y = g_win_y1 + (height * (g_current_zoom_factor - 1)) / (2 * g_current_zoom_factor);
        
        printf("\nZoom %dx na Janela. Offset Calc: (%d, %d)\n", g_current_zoom_factor, offset_x, offset_y);
    } else {
        printf("\nZoom %dx Tela Cheia.\n", g_current_zoom_factor);
    }

    pthread_mutex_lock(&fpga_mutex);
    coproc_apply_zoom_with_offset(algo, offset_x, offset_y);
    coproc_wait_done();
    pthread_mutex_unlock(&fpga_mutex);
}

int main(int argc, char *argv[]) {
    pthread_t thread;
    if (setup_memory_map() != 0) return 1;

    pthread_mutex_lock(&fpga_mutex);
    coproc_reset_image();
    coproc_wait_done();
    pthread_mutex_unlock(&fpga_mutex);

    if (pthread_create(&thread, NULL, mouse_thread_func, NULL) != 0) return 1;

    set_terminal_mode();
    print_menu();

    while (g_program_running) {
        print_status_bar();
        char c = getchar();
        if (c == 'q' || c == 'Q') { g_program_running = false; break; }

        switch (c) {
            case '+':
            case 'i': 
            case 'I': handle_zoom(1); break;
            case 'O': 
            case 'o':
            case '-': handle_zoom(-1); break;
            case 'l': 
            case 'L':
                restore_terminal_mode();
                char f[256]; printf("\nArquivo: "); scanf("%255s", f);
                load_bmp_image(f);
                coproc_reset_image(); coproc_wait_done();
                g_current_zoom_factor = 1;
                set_terminal_mode();
                print_menu(); // Re-imprime o menu após carregar
                break;
            case 'r':
            case 'R':
                printf("\nResetando...\n");
                pthread_mutex_lock(&fpga_mutex);
                coproc_reset_image(); coproc_wait_done();
                coproc_set_window_active(0);
                pthread_mutex_unlock(&fpga_mutex);
                g_win_state = WIN_STATE_IDLE; 
                g_current_zoom_factor = 1; 
                break;
            case 'n': 
            case 'N':
                current_zoom_in_mode = !current_zoom_in_mode; 
                break;
            case 'm': 
            case 'M':
                current_zoom_out_mode = !current_zoom_out_mode; 
                break;
            
            case 'h':
            case 'H':
                restore_terminal_mode(); // Restaura para garantir quebra de linha correta
                print_menu();
                set_terminal_mode();     // Volta para modo raw
                break;
        }
    }
    restore_terminal_mode();
    pthread_join(thread, NULL);
    cleanup_memory_map();
    printf("\nEncerrado.\n");
    return 0;
}