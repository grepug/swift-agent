# E2E 测试实现 Checklist

## Phase 1: 基础设施 🏗️

- [ ] 创建 `Tests/SwiftAgentCoreTests/EndToEndTests.swift` 文件
- [ ] 实现 `MockLanguageModel` 类
  - [ ] 支持预设响应队列
  - [ ] 实现 `LanguageModel` 协议
  - [ ] 添加响应计数器
- [ ] 创建测试辅助函数
  - [ ] `setupTestEnvironment()` - 创建 AgentCenter + Storage + Mock Model
  - [ ] `createTestAgent()` - 创建测试用的 Agent
  - [ ] `createTestSession()` - 创建测试用的 Session
- [ ] 验证基础设施可以编译和运行

---

## Phase 2: 核心执行测试 ⚙️

### 测试 1: 单次执行无历史

- [ ] 编写 `testBasicAgentExecution()` 函数
- [ ] 创建 Session
- [ ] 运行 Agent 一次（loadHistory = false）
- [ ] 验证 Run 的基本属性
  - [ ] agentId 正确
  - [ ] sessionId 正确
  - [ ] userId 正确
  - [ ] status == .completed
- [ ] 验证 Run.messages
  - [ ] 包含 user 消息
  - [ ] 包含 assistant 消息
  - [ ] 消息顺序正确
- [ ] 验证 Storage 状态
  - [ ] Session.runs.count == 1
  - [ ] Run 被正确保存
- [ ] 运行测试并通过

### 测试 2: 历史加载

- [ ] 编写 `testHistoryLoading()` 函数
- [ ] 第一次运行 Agent（创建历史）
- [ ] 第二次运行 Agent（loadHistory = true）
- [ ] 验证第二次运行的 transcript 包含历史
- [ ] 验证 Session.runs.count == 2
- [ ] 验证两次 Run 的消息都正确保存
- [ ] 运行测试并通过

### 测试 3: 多轮对话

- [ ] 编写 `testMultiTurnConversation()` 函数
- [ ] 设置 Mock Model 的 3 个响应
- [ ] 运行 3 轮对话
- [ ] 验证 Session.runs.count == 3
- [ ] 验证 session.allMessages 包含 6 条消息
- [ ] 验证 session.messageCount == 6
- [ ] 验证消息时间顺序正确
- [ ] 运行测试并通过

---

## Phase 3: Session 管理测试 📁

### 测试 4: Session 不存在错误

- [ ] 编写 `testSessionNotFoundError()` 函数
- [ ] 创建不存在的 sessionId
- [ ] 尝试运行 Agent
- [ ] 验证抛出 `AgentError.sessionNotFound`
- [ ] 验证错误信息包含正确的 sessionId
- [ ] 运行测试并通过

### 测试 5: 跨 Session 隔离

- [ ] 编写 `testCrossSessionIsolation()` 函数
- [ ] 创建两个 Session（同一 Agent）
- [ ] Session A 运行 3 次
- [ ] Session B 运行 2 次
- [ ] 验证 Session A 有 3 个 runs
- [ ] 验证 Session B 有 2 个 runs
- [ ] 验证历史不会跨 Session
- [ ] 运行测试并通过

---

## Phase 4: 存储持久化测试 💾

### 测试 6: FileStorage 持久化

- [ ] 编写 `testFileStoragePersistence()` 函数
- [ ] 创建临时目录
- [ ] 使用 FileAgentStorage
- [ ] 创建 Session 并运行 Agent
- [ ] 销毁 AgentCenter
- [ ] 重新创建 AgentCenter（同一目录）
- [ ] 加载 Session
- [ ] 验证 Runs 数据完整
- [ ] 验证 Messages 数据完整
- [ ] 清理临时目录
- [ ] 运行测试并通过

### 测试 7: Storage 统计

- [ ] 编写 `testStorageStats()` 函数
- [ ] 创建 3 个 Session
- [ ] 每个运行不同次数
- [ ] 调用 `storage.getStats()`
- [ ] 验证 totalSessions
- [ ] 验证 totalRuns
- [ ] 验证 totalMessages（从 runs 计算）
- [ ] 验证时间范围
- [ ] 运行测试并通过

---

## Phase 5: 错误处理测试 ❌

### 测试 8: Agent 不存在

- [ ] 编写 `testAgentNotFound()` 函数
- [ ] 创建 Session（不存在的 agentId）
- [ ] 尝试创建 Session
- [ ] 验证抛出 `AgentError.agentNotFound`
- [ ] 运行测试并通过

### 测试 9: Model 不存在

- [ ] 编写 `testModelNotFound()` 函数
- [ ] 创建 Agent（不存在的 modelName）
- [ ] 注册 Agent（不注册 Model）
- [ ] 尝试运行
- [ ] 验证错误处理
- [ ] 运行测试并通过

### 测试 10: 空消息处理

- [ ] 编写 `testEmptyMessage()` 函数
- [ ] 运行 Agent（message = ""）
- [ ] 验证能正常处理或给出合理错误
- [ ] 运行测试并通过

---

## Phase 6: 验证和清理 ✅

- [ ] 运行所有新测试（`swift test`）
- [ ] 确保所有测试通过
- [ ] 检查测试覆盖率
- [ ] 代码 Review
  - [ ] 测试代码清晰易读
  - [ ] 没有重复代码
  - [ ] 辅助函数设计合理
- [ ] 更新文档（如需要）
- [ ] Git commit
  - [ ] 提交 MockLanguageModel
  - [ ] 提交所有测试
  - [ ] 提交文档更新
- [ ] 庆祝完成 🎉

---

## 进度追踪

**开始时间**: **\_\_\_**  
**预计完成**: **\_\_\_**  
**实际完成**: **\_\_\_**

**当前 Phase**: [ ]  
**完成测试数**: 0 / 10  
**遇到的问题**:

-

**学到的经验**:

-

---

## 快速参考

### 运行测试命令

```bash
# 运行所有测试
swift test

# 只运行 E2E 测试
swift test --filter EndToEndTests

# 运行特定测试
swift test --filter testBasicAgentExecution
```

### 常用验证模式

```swift
// 验证成功
#expect(run.status == .completed)

// 验证错误
await #expect(throws: AgentError.self) {
    try await center.runAgent(...)
}

// 验证数组
#expect(session.runs.count == 3)
#expect(messages.count == 6)
```

---

_让我们开始吧！🚀_
