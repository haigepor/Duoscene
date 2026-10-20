# chat

文字输入、实时消息与历史分页；消息去重以 clientMessageId 为准。

当前为模块边界，尚未实现功能。依赖方向为 app -> features -> core。
跨功能流程由 app 应用协调，不建立 feature 之间的循环依赖。
