from PIL import Image, ImageOps, ImageDraw

def round_image(image_path, output_path):
    # Abre a imagem
    img = Image.open(image_path).convert("RGBA")
    
    # Cria uma máscara circular
    size = img.size
    mask = Image.new('L', size, 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0) + size, fill=255)
    
    # Aplica a máscara
    output = ImageOps.fit(img, mask.size, centering=(0.5, 0.5))
    output.putalpha(mask)
    
    # Salva o resultado
    output.save(output_path)
    print(f"Icon saved: {output_path}")

# Arredonda os dois tamanhos
round_image('static/img/icon-192x192.png', 'static/img/icon-192x192.png')
round_image('static/img/icon-512x512.png', 'static/img/icon-512x512.png')
