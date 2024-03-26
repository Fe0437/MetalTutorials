# 🤟 MetalTutorials 🎸

Welcome to MetalTutorials, a step-by-step guide designed to assist you in creating your own Metal Renderer. The main objectives of these tutorials are:
- To maintain minimal code
- To introduce minimal additions in each tutorial
This approach helps the reader understand the changes as we progress in building the engine.

## External Links 🌎

Metal : https://developer.apple.com/metal/

## Getting Started 🏁

Clone this repository and open the project in Xcode.
Each tutorial is structured to build upon the last, starting with the fundamentals and gradually introducing more sophisticated rendering techniques.

Open the file `MTMetalTuorialsApp.swift` you will find :

```swift
@main
struct MetalTutorialsApp: App {
    var body: some Scene {
        WindowGroup {
            // substitute here to choose the tutorial
            MT1ContentView()
        }
    }
}
```

Each tutorial has its own ContentView, named MT[tutorial-number]ContentView. 
To test a specific tutorial, simply replace the number (e.g., MT1ContentView -> MT2ContentView).

Every tutorial is self-contained, allowing you to make modifications without affecting other tutorials.

### Tutorials Overview 👈

* **Tutorial 1** - Hello
Begin your Metal journey by rendering a simple triangle. This tutorial lays the foundation, introducing the basic setup required to render your first Metal frame.

<img width="564" alt="image" src="https://github.com/Fe0437/MetalTutorials/assets/7310503/b551e9a3-4147-4071-9386-7726dc35934d">

* **Tutorial 2** - Sample Object
Advance to loading and rendering a 3D object (.obj) with a basic point light, building upon the skills acquired in Tutorial 1.

  ![Bunny Obj Sample](https://github.com/Fe0437/MetalTutorials/assets/7310503/aba37ab2-b65d-4bc4-9ed2-9ca20e0e4d9b)


* **Tutorial 3** - Deferred Rendering
Learn about deferred rendering techniques. Introduced also camera movement with SwiftUI.

![Bunny Deferred](https://github.com/Fe0437/MetalTutorials/assets/7310503/928668aa-ba0a-4312-9ab8-85c65a963219)
<img width="330" alt="image" src="https://github.com/Fe0437/MetalTutorials/assets/7310503/6150b4f0-6fff-46dc-8fa8-b6df6f02dd92">

* **Tutorial 4** - Shadow Mapping
Explore shadow rendering using shadow maps.

![Screen Recording 2024-03-26 at 08 50 16](https://github.com/Fe0437/MetalTutorials/assets/7310503/f2d72b01-4732-4848-a3d7-ba9b27ce9e97)

* **Tutorial 5** - Tiled Rendering
Metal Tiled Rendering. Avoid to store GBuffer textures.

<img width="564" alt="image" src="https://github.com/Fe0437/MetalTutorials/assets/7310503/6be58513-1cf6-4f31-8013-9c687703c4ba">

* **Tutorial 6** - GPU Rendering
GPU based rendering pipeline. Indirect Command buffers, Argument Buffers, GPU Heap for textures and USDZ loading.

![Screen Recording 2024-03-26 at 08 56 59](https://github.com/Fe0437/MetalTutorials/assets/7310503/a06103fc-a7e4-4f50-a820-8c3a21fd892c)
<img width="330" alt="image" src="https://github.com/Fe0437/MetalTutorials/assets/7310503/1ea28b7f-a489-4b57-95ce-220ff0a4e0d1">


## Contributing 🖋️

Contributions to MetalTutorials are welcome! Whether it's submitting bug reports, feature requests, or code contributions, your input is valuable.
Commit messages follow the [gitmoji convention](https://gitmoji.dev).

## Contact 📞

For any questions or feedback regarding MetalTutorials, feel free to open an issue in this repository or contact me directly.
I'm always open to networking opportunities and collaborations. Feel free to reach out to me! :beers:
