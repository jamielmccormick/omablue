import Darwin
import Foundation

do {
    var data = Data()
    while data.count < 128 * 1024 {
        guard let chunk = try FileHandle.standardInput.read(upToCount: 16_384), !chunk.isEmpty else {
            break
        }
        data.append(chunk)
    }
    try FileHandle.standardOutput.write(contentsOf: data)
} catch {
    exit(1)
}
