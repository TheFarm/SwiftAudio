//
//  AudioPlayer.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 15/03/2018.
//

import Foundation
import MediaPlayer

public typealias AudioPlayerState = AVPlayerWrapperState

/**
 The repeat mode of currently playing track
 */
public enum AudioPlayerRepeatMode: String {

    /// No repeat, will stop playing when the track is ended
    case none

    /// Repeats the current queue(or item) indefinitely
    case queue
    
    /// Repeats the current item indefinitely
    case track
    
    /// Converts from AudioPlayerRepeatMode to MPRepeatType.
    var mpType: MPRepeatType {
        switch self {
        case .none:
            return .off
        case .queue:
            return .all
        case .track:
            return .one
        }
    }
}

public class AudioPlayer: AVPlayerWrapperDelegate {
    
    private var _wrapper: AVPlayerWrapperProtocol
    
    /// The wrapper around the underlying AVPlayer
    var wrapper: AVPlayerWrapperProtocol {
        return _wrapper
    }
    
    public let nowPlayingInfoController: NowPlayingInfoControllerProtocol
    public let remoteCommandController: RemoteCommandController
    public let event = EventHolder()
    
    var _currentItem: AudioItem?
    public var currentItem: AudioItem? {
        return _currentItem
    }
    
    /**
     Set the repeat mode of current track or queue
     */
    public var repeatMode: AudioPlayerRepeatMode = .none
    
    /**
     Set this to false to disable automatic updating of now playing info for control center and lock screen.
     */
    public var automaticallyUpdateNowPlayingInfo: Bool = true
    
    /**
     Controls the time pitch algorithm applied to each item loaded into the player.
     If the loaded `AudioItem` conforms to `TimePitcher`-protocol this will be overriden.
     */
    public var audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm = .lowQualityZeroLatency
    
    /**
     Default remote commands to use for each playing item
     */
    public var remoteCommands: [RemoteCommand] = []
    
    
    // MARK: - Getters from AVPlayerWrapper
    
    /**
     The elapsed playback time of the current item.
     */
    public var currentTime: Double {
        return wrapper.currentTime
    }
    
    /**
     The duration of the current AudioItem.
     */
    public var duration: Double {
        return wrapper.duration
    }
    
    /**
     The bufferedPosition of the current AudioItem.
     */
    public var bufferedPosition: Double {
        return wrapper.bufferedPosition
    }
    
    /**
     The current state of the underlying `AudioPlayer`.
     */
    public var playerState: AudioPlayerState {
        return wrapper.state
    }
    
    // MARK: - Setters for AVPlayerWrapper
    
    /**
     Adjusts the precision when seeking, a smaller value than the standard CMTime.positiveInfinity will incur a
     performance penalty (e.g seeking may be delayed because of decoding delay).
     
     Set to CMTime.zero for sample accurate seeking
     */
    public var seekToleranceBefore: CMTime {
        get { return wrapper.seekToleranceBefore }
        set { _wrapper.seekToleranceBefore = newValue }
    }
    
    /**
     Same as seekToleranceBefore.
     
     The time seeked to will be within the range [time-beforeTolerance, time+afterTolerance],
     and may differ from the specified time for efficiency.
     
     [Read more from Apple Documentation](https://developer.apple.com/documentation/avfoundation/avplayer/1387741-seek)
     [A good explanation on why seeking is inaccurate in some MP3 files](https://exoplayer.dev/troubleshooting.html#why-is-seeking-inaccurate-in-some-mp3-files)
     */
    public var seekToleranceAfter: CMTime {
        get { return wrapper.seekToleranceAfter }
        set { _wrapper.seekToleranceAfter = newValue }
    }
    
    /**
     The amount of seconds to be buffered by the player. Default value is 0 seconds, this means the AVPlayer will choose an appropriate level of buffering.
     
     [Read more from Apple Documentation](https://developer.apple.com/documentation/avfoundation/avplayeritem/1643630-preferredforwardbufferduration)
     
     - Important: This setting will have no effect if `automaticallyWaitsToMinimizeStalling` is set to `true` in the AVPlayer
     */
    public var bufferDuration: TimeInterval {
        get { return wrapper.bufferDuration }
        set { _wrapper.bufferDuration = newValue }
    }
    
    /**
     Set this to decide how often the player should call the delegate with time progress events.
     */
    public var timeEventFrequency: TimeEventFrequency {
        get { return wrapper.timeEventFrequency }
        set { _wrapper.timeEventFrequency = newValue }
    }
    
    /**
     Indicates whether the player should automatically delay playback in order to minimize stalling
     */
    public var automaticallyWaitsToMinimizeStalling: Bool {
        get { return wrapper.automaticallyWaitsToMinimizeStalling }
        set { _wrapper.automaticallyWaitsToMinimizeStalling = newValue }
    }
    
    public var volume: Float {
        get { return wrapper.volume }
        set { _wrapper.volume = newValue }
    }
    
    public var isMuted: Bool {
        get { return wrapper.isMuted }
        set { _wrapper.isMuted = newValue }
    }

    public var rate: Float {
        get { return wrapper.rate }
        set { _wrapper.rate = newValue }
    }
    
    // MARK: - Init
    
    /**
     Create a new AudioPlayer.
     
     - parameter infoCenter: The InfoCenter to update. Default is `MPNowPlayingInfoCenter.default()`.
     */
    public init(nowPlayingInfoController: NowPlayingInfoControllerProtocol = NowPlayingInfoController(),
                remoteCommandController: RemoteCommandController = RemoteCommandController()) {
        self._wrapper = AVPlayerWrapper()
        self.nowPlayingInfoController = nowPlayingInfoController
        self.remoteCommandController = remoteCommandController
        
        self._wrapper.delegate = self
        self.remoteCommandController.audioPlayer = self
    }
    
    // MARK: - Player Actions
    
    /**
     Load an AudioItem into the manager.
     
     - parameter item: The AudioItem to load. The info given in this item is the one used for the InfoCenter.
     - parameter playWhenReady: Immediately start playback when the item is ready. Default is `true`. If you disable this you have to call play() or togglePlay() when the `state` switches to `ready`.
     */
    public func load(item: AudioItem, playWhenReady: Bool = true) throws {
        let url: URL
        switch item.getSourceType() {
        case .stream:
            if let itemUrl = URL(string: item.getSourceUrl()) {
                url = itemUrl
            }
            else {
                throw APError.LoadError.invalidSourceUrl(item.getSourceUrl())
            }
        case .file:
            url = URL(fileURLWithPath: item.getSourceUrl())
        }
        
        wrapper.load(from: url,
                     playWhenReady: playWhenReady,
                     initialTime: (item as? InitialTiming)?.getInitialTime(),
                     options:(item as? AssetOptionsProviding)?.getAssetOptions())
        
        self._currentItem = item
        
        if (automaticallyUpdateNowPlayingInfo) {
            self.loadNowPlayingMetaValues()
        }
        enableRemoteCommands(forItem: item)
    }
    
    /**
     Toggle playback status.
     */
    public func togglePlaying() {
        self.wrapper.togglePlaying()
    }
    
    /**
     Start playback
     */
    public func play() {
        self.wrapper.play()
    }
    
    /**
     Pause playback
     */
    public func pause() {
        self.wrapper.pause()
    }
    
    /**
     Stop playback, resetting the player.
     */
    public func stop() {
        self.reset()
        self.wrapper.stop()
        self.event.playbackEnd.emit(data: (
            reason: .playerStopped,
            currentItem: self.currentItem,
            currentTime: self.currentTime,
            nextItem: nil
        ))
    }
    
    /**
     Seek to a specific time in the item.
     */
    public func seek(to seconds: TimeInterval) {
        if automaticallyUpdateNowPlayingInfo {
            self.updateNowPlayingCurrentTime(seconds)
        }
        self.wrapper.seek(to: seconds)
    }

    /**
     Seek to a specific time in the item with specific tolerance.
     */
    public func seek(to seconds: TimeInterval, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        if automaticallyUpdateNowPlayingInfo {
            self.updateNowPlayingCurrentTime(seconds)
        }
        self.wrapper.seek(to: seconds, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
    }
    
    // MARK: - Remote Command Center
    
    func enableRemoteCommands(_ commands: [RemoteCommand]) {
        self.remoteCommandController.enable(commands: commands)
    }
    
    func enableRemoteCommands(forItem item: AudioItem) {
        if let item = item as? RemoteCommandable {
            self.enableRemoteCommands(item.getCommands())
        }
        else {
            self.enableRemoteCommands(remoteCommands)
        }
    }
    
    // MARK: - NowPlayingInfo
    
    /**
     Loads NowPlayingInfo-meta values with the values found in the current `AudioItem`. Use this if a change to the `AudioItem` is made and you want to update the `NowPlayingInfoController`s values.
     
     Reloads:
     - Artist
     - Title
     - Album title
     - Album artwork
     */
    public func loadNowPlayingMetaValues() {
        guard let item = currentItem else { return }
        
        nowPlayingInfoController.set(keyValues: [
            MediaItemProperty.artist(item.getArtist()),
            MediaItemProperty.title(item.getTitle()),
            MediaItemProperty.albumTitle(item.getAlbumTitle()),
        ])
        
        loadArtwork(forItem: item)
    }
    
    /**
     Resyncs the playbackvalues of the currently playing `AudioItem`.
     
     Will resync:
     - Current time
     - Duration
     - Playback rate
     */
    public func updateNowPlayingPlaybackValues() {
        updateNowPlayingDuration(duration)
        updateNowPlayingCurrentTime(currentTime)
        updateNowPlayingRate(rate)
    }
    
    public func updateRemoteCommands() {
        enableRemoteCommands(remoteCommands)
    }
    
    private func updateNowPlayingDuration(_ duration: Double) {
        nowPlayingInfoController.set(keyValue: MediaItemProperty.duration(duration))
    }
    
    private func updateNowPlayingRate(_ rate: Float) {
        nowPlayingInfoController.set(keyValue: NowPlayingInfoProperty.playbackRate(Double(rate)))
    }
    
    private func updateNowPlayingCurrentTime(_ currentTime: Double) {
        nowPlayingInfoController.set(keyValue: NowPlayingInfoProperty.elapsedPlaybackTime(currentTime))
    }
    
    private func loadArtwork(forItem item: AudioItem) {
        item.getArtwork { (image) in
            if let image = image {
                let artwork = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { (size) -> UIImage in
                    return image
                })
                self.nowPlayingInfoController.set(keyValue: MediaItemProperty.artwork(artwork))
            }
        }
    }
    
    // MARK: - Private
    
    func reset() {
        self._currentItem = nil
    }
    
    private func setTimePitchingAlgorithmForCurrentItem() {
        if let item = currentItem as? TimePitching {
            wrapper.currentItem?.audioTimePitchAlgorithm = item.getPitchAlgorithmType()
        }
        else {
            wrapper.currentItem?.audioTimePitchAlgorithm = audioTimePitchAlgorithm
        }
    }
    
    // MARK: - AVPlayerWrapperDelegate
    
    func AVWrapper(didChangeState state: AVPlayerWrapperState) {
        switch state {
        case .ready, .loading:
            if (automaticallyUpdateNowPlayingInfo) {
                updateNowPlayingPlaybackValues()
            }
            setTimePitchingAlgorithmForCurrentItem()
        case .playing, .paused:
            if (automaticallyUpdateNowPlayingInfo) {
                updateNowPlayingPlaybackValues()
            }
        default: break
        }
        self.event.stateChange.emit(data: state)
    }
    
    func AVWrapper(secondsElapsed seconds: Double) {
        self.event.secondElapse.emit(data: seconds)
    }
    
    func AVWrapper(failedWithError error: Error?) {
        self.event.fail.emit(data: error)
    }
    
    func AVWrapper(seekTo seconds: Double, didFinish: Bool) {
        if !didFinish && automaticallyUpdateNowPlayingInfo {
            updateNowPlayingCurrentTime(currentTime)
        }
        self.event.seek.emit(data: (seconds, didFinish))
    }
    
    func AVWrapper(didUpdateDuration duration: Double) {
        self.event.updateDuration.emit(data: duration)
    }
    
    func AVWrapperItemDidPlayToEndTime() {
        self.event.playbackEnd.emit(data: (
            reason: .playedUntilEnd,
            currentItem: self.currentItem,
            currentTime: self.currentTime,
            nextItem: self.repeatMode != .none ? self.currentItem : nil
        ))
        
        if self.repeatMode != .none {
            self.wrapper.seek(to: 0)
        }
    }
    
    func AVWrapperDidRecreateAVPlayer() {
        self.event.didRecreateAVPlayer.emit(data: ())
    }
    
}
