import Accelerate
import Foundation

/// A real FFT of one size with its Hann window and its work buffers. The key
/// guesser and the tempo guesser each make their own and use it from one
/// function at a time. It is not shared, and it is not `Sendable`.
final class NookLinkAudioSpectrum {
    let size: Int
    private let log2Size: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private var frame: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var squares: [Float]

    /// Bins 0 up to `size / 2` (exclusive) come out of `magnitudes`.
    var binCount: Int { size / 2 }

    /// Nil when `size` is not a power of two of at least 16.
    init?(size: Int) {
        guard size >= 16, size & (size - 1) == 0 else { return nil }
        let log2Size = vDSP_Length(size.trailingZeroBitCount)
        guard let setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2)) else { return nil }
        self.size = size
        self.log2Size = log2Size
        self.setup = setup
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_DENORM))
        self.window = window
        frame = [Float](repeating: 0, count: size)
        real = [Float](repeating: 0, count: size / 2)
        imaginary = [Float](repeating: 0, count: size / 2)
        squares = [Float](repeating: 0, count: size / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// What a full scale sine of one bin's frequency comes out as, which
    /// lets a caller read magnitudes against a known level: one for full scale.
    var fullScale: Float { Float(size) / 4 }

    /// The magnitudes of the Hann windowed frame that starts at `start` in
    /// `samples`. A frame that runs past the end is padded with zeros. Bin
    /// zero is the DC term, which is left out (set to zero).
    func magnitudes(of samples: [Float], from start: Int, into output: inout [Float]) {
        let available = max(0, min(size, samples.count - start))
        if available > 0 {
            samples.withUnsafeBufferPointer { source in
                frame.withUnsafeMutableBufferPointer { destination in
                    destination.baseAddress!.update(from: source.baseAddress! + start, count: available)
                }
            }
        }
        if available < size {
            for index in available..<size { frame[index] = 0 }
        }
        frame.withUnsafeMutableBufferPointer { values in
            window.withUnsafeBufferPointer { weights in
                vDSP_vmul(values.baseAddress!, 1, weights.baseAddress!, 1, values.baseAddress!, 1, vDSP_Length(size))
            }
        }
        transform()
        if output.count != binCount { output = [Float](repeating: 0, count: binCount) }
        var count = Int32(binCount)
        output.withUnsafeMutableBufferPointer { out in
            squares.withUnsafeBufferPointer { vvsqrtf(out.baseAddress!, $0.baseAddress!, &count) }
        }
        output[0] = 0
    }

    /// Runs the FFT over `frame` and leaves the squared magnitudes in `squares`.
    private func transform() {
        let half = size / 2
        frame.withUnsafeBufferPointer { source in
            real.withUnsafeMutableBufferPointer { realPart in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPart in
                    var split = DSPSplitComplex(realp: realPart.baseAddress!, imagp: imaginaryPart.baseAddress!)
                    source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2Size, FFTDirection(kFFTDirection_Forward))
                    // The real FFT packs the Nyquist term into the imaginary
                    // part of bin zero. Neither is wanted.
                    split.realp[0] = 0
                    split.imagp[0] = 0
                    squares.withUnsafeMutableBufferPointer { out in
                        vDSP_zvmags(&split, 1, out.baseAddress!, 1, vDSP_Length(half))
                    }
                }
            }
        }
        // vDSP's forward real FFT is twice the plain transform. Squared, four times.
        var quarter: Float = 0.25
        squares.withUnsafeMutableBufferPointer { values in
            vDSP_vsmul(values.baseAddress!, 1, &quarter, values.baseAddress!, 1, vDSP_Length(half))
        }
    }
}
