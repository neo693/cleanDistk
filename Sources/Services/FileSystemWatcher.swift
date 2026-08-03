import Foundation
import CoreServices

public final class FileSystemWatcher {
    private var stream: FSEventStreamRef?
    private let path: String
    private let queue = DispatchQueue(label: "com.simons.cleandisk.watcher", qos: .background)
    private let onChange: (String) -> Void

    public init(path: String, onChange: @escaping (String) -> Void) {
        self.path = (path as NSString).expandingTildeInPath
        self.onChange = onChange
    }

    public func start() {
        stop()

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [path] as CFArray
        let latency: TimeInterval = 0.5 // Latency in seconds (coalesces rapid changes)
        
        // Listen to file changes, ignore changes triggered by CleanDisk itself
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | 
            kFSEventStreamCreateFlagUseCFTypes | 
            kFSEventStreamCreateFlagIgnoreSelf
        )

        let callback: FSEventStreamCallback = { (
            streamRef: ConstFSEventStreamRef,
            clientCallBackInfo: UnsafeMutableRawPointer?,
            numEvents: Int,
            eventPaths: UnsafeMutableRawPointer,
            eventFlags: UnsafePointer<FSEventStreamEventFlags>,
            eventIds: UnsafePointer<FSEventStreamEventId>
        ) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            
            // Extract changed paths
            let pathsArray = unsafeBitCast(eventPaths, to: CFArray.self) as! [String]
            for changedPath in pathsArray {
                watcher.onChange(changedPath)
            }
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )

        guard let streamRef = stream else { return }
        FSEventStreamSetDispatchQueue(streamRef, queue)
        FSEventStreamStart(streamRef)
    }

    public func stop() {
        guard let streamRef = stream else { return }
        FSEventStreamStop(streamRef)
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
        stream = nil
    }

    deinit {
        stop()
    }
}
