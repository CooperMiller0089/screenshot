# Screenshot 项目开发规范

## Git 版本管理工作流

### 分支策略
- `main` — 永远保持稳定可发布状态，只接受合并，不直接在上面开发
- `feature/<name>` — 新功能开发，从 main 切出，完成后合并回 main
- `fix/<name>` — Bug 修复分支，同上

### 开发流程（每次新功能/修复）
1. 从 main 切出新分支：`git checkout -b feature/<name>`
2. 在分支上开发、提交
3. 功能完成并测试通过后，合并回 main（no-ff）：
   ```
   git checkout main
   git merge --no-ff feature/<name> -m "merge: <描述>"
   ```
4. 打版本标签（见下方规则）
5. 推送 main 和标签：`git push origin main --tags`
6. 可选：删除已合并的 feature 分支

### 语义化版本号规则（Semantic Versioning）
格式：`vMAJOR.MINOR.PATCH`

| 类型 | 何时递增 | 示例 |
|------|----------|------|
| PATCH | Bug 修复、细节调整，不新增功能 | v1.0.0 → v1.0.1 |
| MINOR | 新增功能，向下兼容 | v1.0.1 → v1.1.0 |
| MAJOR | 破坏性重构或重大重写 | v1.x.x → v2.0.0 |

打标签命令：
```
git tag -a v<version> -m "v<version> - <简短描述>"
```

### 安全约束（不可违反）
- **禁止** `git push --force`
- **禁止** `git reset --hard`（除非用户明确要求）
- **禁止** `--no-verify` 跳过 hooks
- 敏感文件（.env、证书、API Key）不提交，发现时主动提醒

### 版本历史
| 版本 | 内容 |
|------|------|
| v1.0.0 | 初始版本：全屏/区域/滚动截图，全局快捷键 |
| v1.0.1 | 修复滚动截图底部内容缺失（自然退出 + ESC 退出） |
| v1.1.0 | UI 重设计：Claude 设计语言（暖白底色、橙红主色、Georgia 衬线字体） |
