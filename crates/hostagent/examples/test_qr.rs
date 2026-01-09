use qrcode_generator::QrCodeEcc;

fn main() {
    let data = r#"{"ip":"192.168.1.1","port":8443,"fp":"abc123","token":"xyz"}"#;
    
    println!("Testing QR generation with different sizes:");
    
    for size in [21, 25, 29, 33, 37, 41] {
        match qrcode_generator::to_svg_to_string(
            data.as_bytes(),
            QrCodeEcc::Low,
            size,
            None::<&str>,
        ) {
            Ok(svg) => {
                let preview = if svg.len() > 100 { &svg[..100] } else { &svg };
                println!("Size {}: OK (total {} chars)\n  Preview: {}", size, svg.len(), preview);
            }
            Err(e) => println!("Size {}: ERR - {}", size, e),
        }
    }
}
