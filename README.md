
# LensAI: Visual Translation

**Instantly translate text in your photos, right from your share sheet.**

LensAI is a powerful iOS Share Extension that uses on-device machine learning to find and replace foreign-language text in your images. Built with privacy and performance in mind, all processing happens directly on your device.

---

## ✨ Features

- **On-Device Translation**: Uses Apple's native `Translation` framework for fast, private, and offline-capable translations.
- **Seamless Integration**: Works directly from the Photos app (or any app that supports image sharing) via a Share Extension.
- **Smart Text Recognition**: Leverages the `Vision` framework to accurately detect text and its perspective in images.
- **Intelligent Text Grouping**: Sophisticated algorithms group related lines of text (like on a road sign) into a single, clean translation bubble.
- **Adaptive UI**: The user interface for selecting languages and saving the image is built with modern, responsive `SwiftUI`.
- **Context-Aware Rendering**: Translated text is rendered into perspective-correct bubbles that are colored based on the original image's palette for a clean, integrated look.
- **Multi-Language Support**: A dynamic language picker allows you to translate text into dozens of supported languages.

---

## 🛠 Technology Stack

LensAI is built entirely with native Apple frameworks, ensuring optimal performance and privacy.

- **UI**: `SwiftUI` hosted in a `UIKit` Share Extension
- **Text Recognition**: `Vision`
- **Translation**: `Translation`
- **Image Processing & Rendering**: `Core Image` and `Core Graphics`
- **Language & Type Support**: `NaturalLanguage` and `UniformTypeIdentifiers`

---




## 🖼 Screenshots

| Original Image                  | Translated Image                |
|--------------------------------|----------------------------------|
| ![IMG_5010](https://github.com/user-attachments/assets/0df9159c-e9e2-4881-8291-97e65826023c) | ![IMG_C58EEB3EA286-1 (1)](https://github.com/user-attachments/assets/e3f75e1f-2062-43a7-b907-5f1a8399fed0) |

| Language Picker                |
|--------------------------------|
| ![IMG_18060B31FD43-1 (1)](https://github.com/user-attachments/assets/6001569e-ad31-4981-8a92-621f7bef245e) | 

---


## 🚀 How to Use

1. Open the **Photos** app on your iPhone.
2. Select a photo that contains foreign-language text.
3. Tap the **Share** button in the bottom-left corner.
4. Scroll through the list of app activities and select **LensAI**.
5. The translated image will appear. You can select a different target language from the picker at the bottom.
6. Tap **Save & Close** to save the translated image to your photo library.

---

## 🌸 Future Enhancements

- **Smarter Text Color**: Automatically switch between light and dark text for optimal contrast against the generated bubble color.
- **Improved Inpainting**: Explore more advanced `Core Image` techniques to more seamlessly blend the text bubbles with complex backgrounds.
- **Video Translation**: Extend the functionality to translate text found in videos in real-time.
