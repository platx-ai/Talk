//
//  ProcessingStateMachineTests.swift
//  Talk
//
//  处理状态机测试
//

import Testing
import Foundation
@testable import Talk

@Suite("ProcessingStateMachine Tests")
@MainActor
struct ProcessingStateMachineTests {
    
    @Test("初始状态为 idle")
    func initialState() {
        let sm = ProcessingStateMachine()
        #expect(sm.currentState == .idle)
    }
    
    @Test("正常流程：idle → recording → recognizing → polishing → outputting → idle")
    func testNormalWorkflow() async {
        let sm = ProcessingStateMachine()
        
        #expect(sm.transition(to: .recording(startDate: Date(), isEditMode: false)))
        #expect(sm.currentState == .recording(startDate: Date(), isEditMode: false))
        
        #expect(sm.transition(to: .recognizing))
        #expect(sm.currentState == .recognizing)
        
        #expect(sm.transition(to: .polishing))
        #expect(sm.currentState == .polishing)
        
        #expect(sm.transition(to: .outputting))
        #expect(sm.currentState == .outputting)
        
        #expect(sm.transition(to: .idle))
        #expect(sm.currentState == .idle)
    }
    
    @Test("非法转换：idle → polishing")
    func testInvalidTransition() async {
        let sm = ProcessingStateMachine()
        
        #expect(!sm.transition(to: .polishing))
        #expect(sm.currentState == .idle)
    }
    
    @Test("非法转换：recording → polishing (跳过 recognizing)")
    func testSkipRecognizing() async {
        let sm = ProcessingStateMachine()
        
        #expect(sm.transition(to: .recording(startDate: Date(), isEditMode: false)))
        #expect(!sm.transition(to: .polishing))
        #expect(sm.currentState == .recording(startDate: Date(), isEditMode: false))
    }
    
    @Test("错误恢复：error → idle")
    func testErrorRecovery() async {
        let sm = ProcessingStateMachine()
        let error = TalkError.unknown(reason: "test")
        
        sm.forceTransition(to: .error(error))
        #expect(sm.currentState == .error(error))
        
        #expect(sm.transition(to: .idle))
        #expect(sm.currentState == .idle)
    }
    
    @Test("isBusy 检查")
    func testIsBusy() async {
        let sm = ProcessingStateMachine()
        
        #expect(!sm.isBusy)  // idle
        
        sm.transition(to: .recording(startDate: Date(), isEditMode: false))
        #expect(sm.isBusy)
        
        sm.transition(to: .recognizing)
        #expect(sm.isBusy)
        
        sm.transition(to: .error(TalkError.unknown(reason: "test")))
        #expect(!sm.isBusy)  // error 状态不算忙碌
    }
    
    @Test("状态转换回调")
    func testStateChangeCallback() async {
        let sm = ProcessingStateMachine()
        var callbackCalled = false
        var oldStateRecorded: ProcessingState?
        var newStateRecorded: ProcessingState?
        
        sm.onStateChange = { oldState, newState in
            callbackCalled = true
            oldStateRecorded = oldState
            newStateRecorded = newState
        }
        
        sm.transition(to: .recording(startDate: Date(), isEditMode: false))
        
        #expect(callbackCalled)
        #expect(oldStateRecorded == .idle)
        #expect(newStateRecorded == .recording(startDate: Date(), isEditMode: false))
    }
    
    @Test("reset 方法")
    func testReset() async {
        let sm = ProcessingStateMachine()
        
        sm.transition(to: .recording(startDate: Date(), isEditMode: false))
        sm.transition(to: .recognizing)
        
        sm.reset()
        
        #expect(sm.currentState == .idle)
    }
    
    @Test("loadingModel 状态转换")
    func testLoadingModelTransition() async {
        let sm = ProcessingStateMachine()
        
        #expect(sm.transition(to: .loadingModel(modelName: "Qwen3-ASR", progress: 0.5)))
        #expect(sm.currentState == .loadingModel(modelName: "Qwen3-ASR", progress: 0.5))
        
        // 可以从 loadingModel 回到 idle
        #expect(sm.transition(to: .idle))
        
        // 也可以从 loadingModel 到 recording
        sm.transition(to: .loadingModel(modelName: "Qwen3-ASR", progress: 0.0))
        #expect(sm.transition(to: .recording(startDate: Date(), isEditMode: false)))
    }
}
