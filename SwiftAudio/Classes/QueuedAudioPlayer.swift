//
//  QueuedAudioPlayer.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 24/03/2018.
//

import Foundation
import MediaPlayer

/**
 An audio player that can keep track of a queue of AudioItems.
 */
public class QueuedAudioPlayer: AudioPlayer {
    
    let queueManager: QueueManager = QueueManager<AudioItem>()
    
    /**
     Set wether the player should automatically load the next track when a song is finished.
     Default is `true`.
     */
    public var automaticallyLoadNextSong: Bool = true
    
    /**
     Sets wether the player should automatically play the track when loaded.
     Default is `true`
     */
    public var automaticallyPlayWhenReady: Bool = true
    
    /**
     The current item if any.
     */
    public override var currentItem: AudioItem? {
        return queueManager.current
    }
    
    /**
     The next item if any.
     */
    public var nextItem: AudioItem? {
        switch repeatMode {
        case .none:
            return nextItems.first
        case .track:
            return currentItem
        case .queue:
            if nextItems.isEmpty {
                return items.first
            }
            return nextItems.first
        }
    }
    
    /**
     The previous item if any.
     */
    public var previousItem: AudioItem? {
        switch repeatMode {
        case .none:
            return previousItems.last
        case .track:
            return currentItem
        case .queue:
            if previousItems.isEmpty {
                return nextItems.last
            }
            return previousItems.last
        }
    }
    
    
    /**
     The index of the current item.
     */
    public var currentIndex: Int {
        return queueManager.currentIndex
    }
    
    /**
     Clears the queue
     */
    override func reset() {
        queueManager.clearQueue()
    }
    
    /**
     All items currently in the queue.
     */
    public var items: [AudioItem] {
        return queueManager.items
    }
    
    /**
     The previous items held by the queue.
     */
    public var previousItems: [AudioItem] {
        return queueManager.previousItems
    }
    
    /**
     The upcoming items in the queue.
     */
    public var nextItems: [AudioItem] {
        return queueManager.nextItems
    }
    
    /**
     Will replace the current item with a new one and load it into the player.
     
     - parameter item: The AudioItem to replace the current item.
     - parameter playWhenReady: If this is `true` it will automatically start playback.
     - throws: APError.LoadError
     */
    public override func load(item: AudioItem, playWhenReady: Bool) throws {
        try super.load(item: item, playWhenReady: playWhenReady)
        queueManager.replaceCurrentItem(with: item)
    }
    
    /**
     Add a single item to the queue.
     
     - parameter item: The item to add.
     - throws: `APError`
     */
    public func add(item: AudioItem) throws {
        if currentItem == nil {
            queueManager.addItem(item)
            try self.load(item: item, playWhenReady: automaticallyPlayWhenReady)
        }
        else {
            queueManager.addItem(item)
        }
    }
    
    /**
     Add items to the queue.
     
     - parameter items: The items to add to the queue.
     - throws: `APError`
     */
    public func add(items: [AudioItem]) throws {
        if currentItem == nil {
            queueManager.addItems(items)
            
            if let currentItem = self.currentItem {
                try self.load(item: currentItem, playWhenReady: automaticallyPlayWhenReady)
            }
        }
        else {
            queueManager.addItems(items)
        }
    }
    
    public func add(items: [AudioItem], at index: Int) throws {
        try queueManager.addItems(items, at: index)
    }
    
    /**
     Step to the next item in the queue.
     
     - throws: `APError`
     */
    public func next() throws {
        event.playbackEnd.emit(data: (
            reason: .skippedToNext,
            currentItem: self.currentItem,
            currentTime: self.currentTime,
            nextItem: self.nextItem
        ))
        
        var nextItem: AudioItem!
        if repeatMode == .none {
            nextItem = try queueManager.next()
        } else {
            nextItem = try queueManager.nextLooped()
        }

        try self.load(item: nextItem, playWhenReady: automaticallyPlayWhenReady)
    }
    
    /**
     Step to the previous item in the queue.
     */
    public func previous() throws {
        event.playbackEnd.emit(data: (
            reason: .skippedToPrevious,
            currentItem: self.currentItem,
            currentTime: self.currentTime,
            nextItem: self.previousItem
        ))
        var previousItem: AudioItem!
        if repeatMode == .none {
            previousItem = try queueManager.previous()
        } else {
            previousItem = try queueManager.previousLooped()
        }
        
        try self.load(item: previousItem, playWhenReady: automaticallyPlayWhenReady)
    }
    
    /**
     Remove an item from the queue.
     
     - parameter index: The index of the item to remove.
     - throws: `APError.QueueError`
     */
    public func removeItem(at index: Int) throws {
        try queueManager.removeItem(at: index)
    }
    
    /**
     Jump to a certain item in the queue.
     
     - parameter index: The index of the item to jump to.
     - throws: `APError`
     */
    public func jumpToItem(atIndex index: Int) throws {
        event.playbackEnd.emit(data: (
            reason: .jumpedToIndex,
            currentItem: self.currentItem,
            currentTime: self.currentTime,
            nextItem: self.nextItems.first
        ))
        let item = try queueManager.jump(to: index)
        try self.load(item: item, playWhenReady: automaticallyPlayWhenReady)
    }
    
    /**
     Move an item in the queue from one position to another.
     
     - parameter fromIndex: The index of the item to move.
     - parameter toIndex: The index to move the item to.
     - throws: `APError.QueueError`
     */
    func moveItem(fromIndex: Int, toIndex: Int) throws {
        try queueManager.moveItem(fromIndex: fromIndex, toIndex: toIndex)
    }
    
    /**
     Remove all upcoming items, those returned by `next()`
     */
    public func removeUpcomingItems() {
        queueManager.removeUpcomingItems()
    }
    
    /**
     Remove all previous items, those returned by `previous()`
     */
    public func removePreviousItems() {
        queueManager.removePreviousItems()
    }
    
    // MARK: - AVPlayerWrapperDelegate
    
    override func AVWrapperItemDidPlayToEndTime() {
        self.event.playbackEnd.emit(data: (
            reason: .playedUntilEnd,
            currentItem: self.currentItem,
            currentTime: self.currentTime,
            nextItem: self.nextItem
        ))

        if repeatMode != .track && automaticallyLoadNextSong {
            try? self.next()
        } else if repeatMode == .track {
            wrapper.seek(to: 0)
            automaticallyPlayWhenReady ? self.play() : self.pause()
        }
    }
    
}
