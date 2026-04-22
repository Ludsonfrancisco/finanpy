from PIL import Image, ImageDraw

def add_background(image_path, output_path, bg_color=(2, 6, 23, 255)): # Slate-950
    # Abre a imagem arredondada (com transparência)
    img = Image.open(image_path).convert("RGBA")
    
    # Cria um fundo sólido
    background = Image.new("RGBA", img.size, bg_color)
    
    # Cola a imagem sobre o fundo
    background.paste(img, (0, 0), img)
    
    # Salva
    background.save(output_path)
    print(f"Icon updated with solid background: {output_path}")

# Atualiza os ícones
add_background('static/img/icon-192x192.png', 'static/img/icon-192x192.png')
add_background('static/img/icon-512x512.png', 'static/img/icon-512x512.png')
