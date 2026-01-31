# 端到端测试计划 (End-to-End Test Plan)

## 目标

验证 Swift Agent 框架的核心执行流程，从创建 Session 到运行 Agent 再到持久化存储的完整链路。

---

## 测试范围

### ✅ 包含的功能
- Agent 执行的完整生命周期
- Session 创建和管理
- 历史消息加载 (`loadHistory`)
- Run 的创建和存储
- Mock Model 集成
- 基本错误处理

### ❌ 不包含的功能（后续测试）
- 真实 LLM 调用
- 工具执行集成
- MCP Server 集成
- 流式响应
- 并发场景

---

## 测试环境设计

### Mock Model 实现

创建一个简单的 Mock Model 用于测试：

```swift
final class MockLanguageModel: LanguageModel {
    var responses: [String] = []
    var currentResponseIndex = 0
    
    func generate(messages: [Message]) async throws -> String {
        guard currentResponseIndex < responses.count else {
            throw MockError.noMoreResponses
        }
        let response = responses[currentResponseIndex]
        currentResponseIndex += 1
        return response
    }
}
```

### 测试数据准备

- 预定义的用户消息
- 预定义的 Agent 响应
- 固定的 userId 和 agentId
- 临时的测试存储目录

---

## 测试用例详细设计

### Test Suite 1: 基础执行流程

#### 测试 1.1: 单次执行无历史
**目标**: 验证最基本的执行流程

**步骤**:
1. 创建 InMemoryAgentStorage
2. 创建 LiveAgentCenter
3. 注册 Mock Model
4. 注册一个简单 Agent（无工具）
5. 创建 Session
6. 运行 Agent（loadHistory = false）
7. 验证返回的 Run

**验证点**:
- ✓ Run 包含正确的 agentId, sessionId, userId
- ✓ Run.messages 包含 user 和 assistant 消息
- ✓ Run 被正确保存到 storage
- ✓ Session.runs 包含该 Run
- ✓ Run.status == .completed

---

#### 测试 1.2: 多次执行带历史加载
**目标**: 验证历史加载功能

**步骤**:
1. 使用前一个测试的 Session
2. 第二次运行 Agent（loadHistory = true）
3. 验证 Model 收到的消息包含历史

**验证点**:
- ✓ Session.runs.count == 2
- ✓ 第二次运行的 transcript 包含第一次的消息
- ✓ messages 按时间顺序排列
- ✓ 两次 Run 的 messages 都被正确保存

---

#### 测试 1.3: 多轮对话完整流程
**目标**: 模拟真实的多轮对话场景

**步骤**:
1. 创建 Session
2. 运行 3 轮对话：
   - "你好" → "你好！有什么可以帮你的？"
   - "今天天气怎么样？" → "抱歉，我无法获取实时天气信息。"
   - "谢谢" → "不客气！"
3. 每次都 loadHistory = true

**验证点**:
- ✓ Session.runs.count == 3
- ✓ session.allMessages 返回所有 6 条消息（3 user + 3 assistant）
- ✓ session.messageCount == 6
- ✓ allMessages 按时间排序
- ✓ 最后一次运行的 transcript 包含全部历史

---

### Test Suite 2: Session 管理

#### 测试 2.1: Session 不存在时运行失败
**目标**: 验证错误处理

**步骤**:
1. 创建不存在的 sessionId
2. 尝试运行 Agent
3. 期望抛出 AgentError.sessionNotFound

**验证点**:
- ✓ 抛出正确的错误类型
- ✓ 错误包含正确的 sessionId

---

#### 测试 2.2: 跨 Session 隔离
**目标**: 验证不同 Session 之间数据隔离

**步骤**:
1. 创建两个 Session（同一 Agent）
2. 在 Session A 运行 3 次
3. 在 Session B 运行 2 次
4. 验证数据隔离

**验证点**:
- ✓ Session A 有 3 个 runs
- ✓ Session B 有 2 个 runs
- ✓ Session A 的 allMessages 不包含 Session B 的消息
- ✓ 加载历史时只加载当前 Session 的历史

---

### Test Suite 3: Storage 持久化

#### 测试 3.1: FileAgentStorage 持久化验证
**目标**: 验证文件存储的持久化能力

**步骤**:
1. 使用 FileAgentStorage 创建临时目录
2. 创建 Session 并运行 Agent
3. 销毁 AgentCenter
4. 重新创建 AgentCenter（使用同一存储目录）
5. 加载 Session
6. 验证数据完整性

**验证点**:
- ✓ Session 可以被重新加载
- ✓ Runs 数据完整
- ✓ Messages 数据完整
- ✓ 文件目录结构正确（agents/{agentId}/sessions/{timestamp-uuid}/）

---

#### 测试 3.2: 统计信息准确性
**目标**: 验证 getStats() 的准确性

**步骤**:
1. 创建 3 个 Session（2 个 Agent A，1 个 Agent B）
2. 每个 Session 运行不同次数的 Agent
3. 调用 storage.getStats()

**验证点**:
- ✓ totalSessions 正确
- ✓ totalRuns 正确
- ✓ totalMessages 正确（从 runs 计算）
- ✓ oldestSession 和 newestSession 正确

---

### Test Suite 4: 错误处理和边界情况

#### 测试 4.1: Agent 不存在
**目标**: 验证 Agent 不存在时的错误处理

**步骤**:
1. 创建 Session（agentId = "non-existent"）
2. 尝试运行不存在的 Agent
3. 期望抛出 AgentError.agentNotFound

---

#### 测试 4.2: Model 不存在
**目标**: 验证 Model 不存在时的错误处理

**步骤**:
1. 创建 Agent（modelName = "non-existent"）
2. 注册 Agent（但不注册 Model）
3. 创建 Session 并运行
4. 期望 fatalError 或抛出错误

---

#### 测试 4.3: 空消息处理
**目标**: 验证边界情况

**步骤**:
1. 运行 Agent，message = ""
2. 验证能否正常处理

---

## 实现顺序

### Phase 1: 基础设施（30 分钟）
- [ ] 创建 MockLanguageModel
- [ ] 创建测试辅助函数（setupTestEnvironment）
- [ ] 创建 E2E 测试文件

### Phase 2: 核心测试（1 小时）
- [ ] 实现 Test Suite 1.1: 单次执行
- [ ] 实现 Test Suite 1.2: 历史加载
- [ ] 实现 Test Suite 1.3: 多轮对话

### Phase 3: Session 测试（30 分钟）
- [ ] 实现 Test Suite 2.1: Session 不存在
- [ ] 实现 Test Suite 2.2: 跨 Session 隔离

### Phase 4: 存储测试（30 分钟）
- [ ] 实现 Test Suite 3.1: 持久化验证
- [ ] 实现 Test Suite 3.2: 统计信息

### Phase 5: 错误处理（20 分钟）
- [ ] 实现 Test Suite 4.1-4.3: 各种错误场景

### Phase 6: 验证和清理（10 分钟）
- [ ] 运行所有测试
- [ ] 修复发现的问题
- [ ] 代码审查和清理

---

## 成功标准

- ✅ 所有测试通过
- ✅ 代码覆盖核心执行路径
- ✅ 发现并修复至少 0-2 个潜在 bug
- ✅ 测试代码清晰，易于维护
- ✅ 为后续工具集成测试打好基础

---

## 风险和挑战

### 已知风险
1. **Mock Model 集成复杂度**: AnyLanguageModel 的集成可能比预期复杂
2. **Transcript 构建**: 从历史 runs 重建 transcript 的逻辑可能需要调试
3. **并发问题**: Actor 隔离可能导致测试中的异步问题

### 缓解措施
- 从最简单的测试开始
- 每个测试独立运行
- 使用 InMemoryStorage 减少 I/O 复杂度
- 逐步增加复杂度

---

## 下一步行动

1. ✅ 创建此测试计划文档
2. ⏳ Review 并确认计划
3. ⏳ 开始 Phase 1 实现
4. ⏳ 逐步完成各个 Phase
5. ⏳ 最终验证和提交

---

*Created: 2026-01-31*
*Last Updated: 2026-01-31*
