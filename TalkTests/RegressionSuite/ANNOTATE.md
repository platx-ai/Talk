# ASR 回归测试 Ground Truth 标注

每条记录下方是 Qwen3 的输出（可能有错）。请直接修改为你实际说的内容。
修改后保存，我会自动更新 regression_cases.json。

## zh_short_01
- 文件: `6114ED33-A5F1-43C4-B6CA-9F87B7068148.m4a`
- 时长: 3.1s | 语言: zh
- 关键词: 不确定, 实验

**Ground Truth（请修改为正确内容）:**

> 不可，如果不确定，就做实验。

---

## zh_short_02
- 文件: `7E9A42BA-8AD9-44D7-BED3-95BAEDA2B699.m4a`
- 时长: 2.6s | 语言: zh
- 关键词: 更新

**Ground Truth（请修改为正确内容）:**

> 好的，我来更新一版。

---

## zh_medium_01
- 文件: `8C91ADAE-F6E0-482D-8DA9-6BB0E10C77FD.m4a`
- 时长: 9.7s | 语言: zh
- 关键词: 独立, 判断, 上下文, 同意

**Ground Truth（请修改为正确内容）:**

> 对于Review的结果你要有自己独立的判断，因为它的上下文肯定没有你的丰富。所以，你可以同意，也可以不同意。

---

## zh_medium_02
- 文件: `0EEF6F90-0931-413D-A015-9B724FFD5643.m4a`
- 时长: 13.1s | 语言: zh
- 关键词: 同步, 最新状态, 迭代, 改进

**Ground Truth（请修改为正确内容）:**

> 我们同步一下现在最新状态：目前的 SOTA 是一个什么样的水水准。然后，根据上一轮的迭代，下一轮的改进的方向是什么。

---

## zh_medium_03
- 文件: `CC01DE56-10F9-43EA-A142-9100F57A5196.m4a`
- 时长: 13.7s | 语言: zh
- 关键词: 提示词, 注入, 关键词

**Ground Truth（请修改为正确内容）:**

> 有一个是hard line，绝对不能碰的，就是不能通过在提示词中注入具体的关键词和，然后来hack。

---

## zh_medium_04
- 文件: `A18521A9-E5FE-4FF9-BEAA-2375148F1B97.m4a`
- 时长: 10.9s | 语言: zh
- 关键词: 关键词, 作弊

**Ground Truth（请修改为正确内容）:**

> 比如，比如不能提宁德时代，不能提跟我们的 benchmark 相关的任何关键词。这样的是一个作弊的行为。

---

## zh_long_01
- 文件: `60D15531-2FE6-44A8-996A-04A413C85495.m4a`
- 时长: 30.5s | 语言: zh
- 关键词: 实验, 音频, 三十秒, 上限

**Ground Truth（请修改为正确内容）:**

> 开始实现。然后，对于 Gemma 4 的集成，我建议你可以单独起一个 teamate 去做实验，然后探索它的。呃，用我们已经录好的这些音频采集过的，包括现在我跟你说的这些音频都留下来了，可以去做实验。因为 Gemma 4 有一个30秒大概的一个上限，所以其这个要做特殊的处理。

---

## zh_long_02
- 文件: `8BC75D2F-CDE3-45EA-BEFC-9BCD2CCEB26D.m4a`
- 时长: 15.1s | 语言: zh
- 关键词: 反思, 假设, 排序

**Ground Truth（请修改为正确内容）:**

> 另外一个就是，你去反思：我们在程序上面有哪些假设或者是猜测，实际上是没有意义的。比如我们这些排序的依据是什么等等。

---

## en_short_01
- 文件: `085C511D-EC6D-4090-9101-CED25A00FD5A.m4a`
- 时长: 2.4s | 语言: en
- 关键词: think, used

**Ground Truth（请修改为正确内容）:**

> 我觉得可以用。

---

## en_short_02
- 文件: `4ECEECE8-B020-4DCD-B70F-E31A58732F7C.m4a`
- 时长: 3.3s | 语言: en
- 关键词: work

**Ground Truth（请修改为正确内容）:**

> 飞书的 chanel 怎么不工作了？

---

## mixed_medium_01
- 文件: `1E656A70-C1AF-44A0-9191-2B84DCAD800D.m4a`
- 时长: 10.3s | 语言: mixed
- 关键词: Agent SDK, 升级, release

**Ground Truth（请修改为正确内容）:**

> Claude Agent SDK的依赖，把它升级到最新版。然后做一个pre release，部署到Tracy Mini上。

---

## mixed_long_01
- 文件: `B83282FC-1BA9-44D8-96A5-B9EDF8856A8C.m4a`
- 时长: 19.0s | 语言: mixed
- 关键词: CLI, Agent, find evidence

**Ground Truth（请修改为正确内容）:**

> 现在这个CLI和入口是怎么设计的？我应该怎么使用？如果我想让以前使用Sub Agent的方式执行的，主Agent去调用这个CLI去find evidence。

---
