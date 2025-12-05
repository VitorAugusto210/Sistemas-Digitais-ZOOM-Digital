import sys
from PIL import Image

def converter_imagem(input_path, output_path="maca.bmp"):
    try:
        # 1. Abre a imagem original
        with Image.open(input_path) as img:
            print(f"Imagem original: {img.format}, Tamanho: {img.size}, Modo: {img.mode}")

            # 2. Redimensiona para 320x240 (ignorando proporção para caber exato na tela)
            # Se quiser manter a proporção e cortar, a lógica seria diferente.
            # Aqui forçamos o tamanho exato que a FPGA espera.
            img_resized = img.resize((320, 240), Image.Resampling.LANCZOS)

            # 3. Converte para Escala de Cinza (8 bits por pixel)
            # O modo 'L' (Luminância) gera pixels de 0-255 (8 bits), compatível com seu código C
            img_gray = img_resized.convert('L')

            # 4. Salva como BMP
            img_gray.save(output_path, format="BMP")
            
            print(f"✅ Sucesso! Imagem salva em: {output_path}")
            print(f"   Nova resolução: {img_gray.size}")
            print(f"   Novo modo: {img_gray.mode} (8-bit grayscale)")

    except FileNotFoundError:
        print(f"❌ Erro: O arquivo '{input_path}' não foi encontrado.")
    except Exception as e:
        print(f"❌ Erro inesperado: {e}")

if __name__ == "__main__":
    nome_arquivo = "maca.jpg"
    converter_imagem(nome_arquivo)