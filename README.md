# Avante

**Local LLM Writing Assistant | Swift, SwiftUI**

A private, local-first macOS application that uses on-device LLMs for real-time writing analysis. Built with Swift and SwiftUI, Avante demonstrates advanced macOS development techniques and innovative AI integration.

## Features

- **Privacy-First**: All analysis happens locally on your device
- **Real-Time Analysis**: Live writing feedback as you type
- **Smart Context Management**: Novel recursive summarization algorithm overcomes context-window limitations
- **Advanced Metrics**: Novelty, Clarity, and Flow analysis with visual highlighting
- **Focus Mode**: Distraction-free writing environment
- **Native File Management**: Seamless integration with macOS file system
- **Undo/Redo Support**: Full document state management

## Architecture

### Core Technologies
- **SwiftUI**: Modern declarative UI framework
- **FoundationModels**: Apple's on-device LLM framework
- **Combine**: Reactive programming for real-time updates
- **NaturalLanguage**: Text processing and tokenization

### Key Components

#### Analysis Engine
- **Recursive Summarization**: Breaks down large documents into manageable chunks while maintaining global context
- **Context Window Management**: Intelligent handling of local model limitations
- **Real-Time Processing**: Live analysis with debounced input handling

#### UI Architecture
- **MVVM Pattern**: Clean separation of concerns
- **Reactive Bindings**: SwiftUI + Combine for responsive UI
- **Custom Layout Managers**: Advanced text highlighting and metrics display
- **Native File Integration**: Document-based app architecture

## Getting Started

### Prerequisites
- macOS 26.0+ (Tahoe or later)
- Apple Silicon Mac (for optimal LLM performance)

### Installation
1. Clone the repository
2. Open `avante.xcodeproj` in Xcode
3. Build and run the project

### Usage
1. Open a text file or create a new document
2. Start typing to see real-time analysis
3. Use the metrics sidebar to view detailed feedback
4. Toggle focus mode for distraction-free writing

## Technical Highlights

### Recursive Summarization Algorithm
The application implements a novel approach to handling large documents by breaking them into manageable chunks while preserving global context. This allows local models to understand document-wide patterns despite their limited context windows.

### Real-Time Analysis Pipeline
- **Input Debouncing**: Prevents excessive API calls
- **Context Preservation**: Maintains document coherence across chunks
- **Metrics Aggregation**: Combines local insights into global understanding

### Performance Optimizations
- **Lazy Loading**: Efficient memory management for large documents
- **Background Processing**: Non-blocking analysis operations
- **Smart Caching**: Reduces redundant computations

## Screenshots

*Screenshots will be added here once provided*

## Project Goals

This project demonstrates:
- **Advanced SwiftUI Development**: Complex UI patterns and state management
- **AI Integration**: Seamless on-device LLM integration
- **Performance Engineering**: Optimized for real-time processing
- **macOS Best Practices**: Native app architecture and user experience

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with Apple's FoundationModels framework
- Inspired by modern writing assistant applications
- Demonstrates advanced SwiftUI and Combine patterns

---

**Note**: This project is designed as a technical demonstration of advanced iOS/macOS development capabilities, particularly in the areas of AI integration, real-time processing, and native app architecture.
