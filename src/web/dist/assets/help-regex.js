import{_ as sfc,d as defineComponent,g as createBlock,o as openBlock}from"./index-DYc8clNA.js";

const PAGE_HTML = String.raw`<style>
.qlregex-page{max-width:1080px;margin:0 auto;padding:20px 20px 56px;color:var(--color-text-1);font-size:14px;line-height:1.78;word-break:break-word}
.qlregex-page *{box-sizing:border-box}
.qlregex-hd h1{font-size:22px;line-height:1.4;margin:0 0 6px;font-weight:600}
.qlregex-hd>p{margin:0;color:var(--color-text-3);font-size:13px}
.qlregex-card{background:var(--color-bg-2);border:1px solid var(--color-border-2);border-radius:8px;padding:18px 20px 20px;margin-top:16px}
.qlregex-card>h2{font-size:16px;line-height:1.5;margin:0 0 4px;font-weight:600;display:flex;align-items:center;gap:8px}
.qlregex-card>h2::before{content:"";flex:none;width:3px;height:15px;border-radius:2px;background:var(--color-primary-6)}
.qlregex-card>h2+.qlregex-sub{margin:0 0 12px;color:var(--color-text-3);font-size:12.5px}
.qlregex-card h3{font-size:14px;margin:18px 0 8px;font-weight:600;color:var(--color-text-1)}
.qlregex-card h3:first-of-type{margin-top:12px}
.qlregex-page p{margin:8px 0}
.qlregex-page ul,.qlregex-page ol{margin:8px 0;padding-left:22px}
.qlregex-page li{margin:4px 0}
.qlregex-page code{background:var(--color-fill-2);border:1px solid var(--color-border-1);border-radius:4px;padding:1px 5px;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,"Liberation Mono",monospace;font-size:12.5px;color:var(--color-text-1);white-space:nowrap}
.qlregex-page pre{margin:10px 0;background:var(--color-fill-1);border:1px solid var(--color-border-1);border-radius:6px;padding:12px 14px;overflow:auto}
.qlregex-page pre code{background:none;border:none;padding:0;font-size:12.5px;line-height:1.72;white-space:pre}
.qlregex-page table{width:100%;border-collapse:collapse;margin:10px 0;font-size:13px}
.qlregex-page th,.qlregex-page td{border:1px solid var(--color-border-2);padding:8px 10px;text-align:left;vertical-align:top}
.qlregex-page th{background:var(--color-fill-2);font-weight:600;white-space:nowrap}
.qlregex-page tbody tr:hover{background:var(--color-fill-1)}
.qlregex-page td code{white-space:nowrap}
.qlregex-note{margin:12px 0;padding:10px 14px;border-radius:6px;border-left:3px solid;font-size:13px}
.qlregex-note:first-child{margin-top:0}
.qlregex-note p:first-child{margin-top:0}
.qlregex-note p:last-child{margin-bottom:0}
.qlregex-note.ok{background:var(--color-success-light-1);border-color:var(--success-6)}
.qlregex-note.warn{background:var(--color-warning-light-1);border-color:var(--warning-6)}
.qlregex-note.bad{background:var(--color-danger-light-1);border-color:var(--danger-6)}
.qlregex-note b{font-weight:600}
.qlregex-badge{display:inline-block;padding:0 6px;border-radius:4px;font-size:12px;line-height:18px;border:1px solid;white-space:nowrap}
.qlregex-badge.y{color:var(--success-6);background:var(--color-success-light-1);border-color:var(--success-6)}
.qlregex-badge.n{color:var(--danger-6);background:var(--color-danger-light-1);border-color:var(--danger-6)}
.qlregex-steps{counter-reset:qlst;list-style:none;padding:0;margin:12px 0}
.qlregex-steps>li{counter-increment:qlst;position:relative;padding-left:34px;margin:10px 0}
.qlregex-steps>li::before{content:counter(qlst);position:absolute;left:0;top:3px;width:22px;height:22px;border-radius:50%;background:var(--color-primary-light-2);color:var(--color-primary-6);font-size:12px;font-weight:600;display:flex;align-items:center;justify-content:center}
.qlregex-flow{display:flex;flex-wrap:wrap;align-items:stretch;gap:10px;margin:12px 0}
.qlregex-flow>div{flex:1 1 180px;min-width:160px;border:1px solid var(--color-border-2);border-radius:6px;padding:10px 12px;background:var(--color-fill-1);font-size:12.5px;line-height:1.7}
.qlregex-flow>div>b{display:block;font-size:12px;color:var(--color-primary-6);margin-bottom:4px;font-weight:600}
.qlregex-kv{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12.5px;white-space:nowrap}
</style>
<div class="qlregex-page">

  <div class="qlregex-hd">
    <h1>正则使用规则</h1>
    <p>变量管理 → 新增 / 编辑变量 里的「匹配正则」「多值分隔符」「账号字段分隔符」到底怎么用</p>
  </div>

  <div class="qlregex-card">
    <h2>先记住一句话</h2>
    <div class="qlregex-note ok">
      <p><b>正则在本系统里只做「提取」，不做「校验」。</b>它从用户提交的内容里<b>抠出第一段匹配到的文字</b>，用这段文字去替换原始提交值。匹配不到时，不同模式的处理方式不同（见下文）。</p>
    </div>
    <p>因此不要把它当「格式校验器」来写。写 <code class="qlregex-kv">[0-9]+</code> 的意思不是「必须是纯数字，否则报错」，而是「把里面第一串数字抠出来，其余丢掉」。</p>
  </div>

  <div class="qlregex-card">
    <h2>两个正则分别在哪生效</h2>
    <p class="qlregex-sub">表单里两个输入框都叫「匹配正则」，靠「模式」区分，别填错位置。</p>
    <table>
      <thead>
        <tr><th>字段</th><th>生效模式</th><th>作用</th></tr>
      </thead>
      <tbody>
        <tr>
          <td><code>regex</code><br>（表单显示为「匹配正则」，选中模式时才出现）</td>
          <td>新建模式<br>（mode = 1）</td>
          <td>对提交值执行「找第一段匹配」，把<b>匹配结果</b>作为最终写入值送进青龙面板。匹配不到 → 直接拒绝提交。</td>
        </tr>
        <tr>
          <td><code>regex_update</code><br>（表单显示为「匹配正则」，选更新模式时才出现）</td>
          <td>更新模式<br>（mode = 2）</td>
          <td><b>只在「账号字段分隔符」留空时生效</b>，用来提取「账号标识」做判重。</td>
        </tr>
      </tbody>
    </table>
    <div class="qlregex-note warn">
      <p>两个字段在数据库里是分开的两列，只是表单标题都叫「匹配正则」。选「新建模式」时填的是前者，选「更新模式」时填的是后者，服务端按模式各取各的，不存在覆盖关系。</p>
    </div>
  </div>

  <div class="qlregex-card">
    <h2>新建模式（mode = 1）的正则行为</h2>
    <table>
      <thead><tr><th>变量是否填了正则</th><th>结果</th></tr></thead>
      <tbody>
        <tr><td>没填</td><td>提交值原样写入面板。</td></tr>
        <tr><td>填了</td><td>对提交值找第一段匹配，<b>匹配结果即最终写入值</b>；原始值中未匹配的部分被丢弃。</td></tr>
        <tr><td>填了但匹配不到</td><td>拒绝提交，接口返回 <code>变量值格式不符合要求</code>，任何面板都不会写入。</td></tr>
      </tbody>
    </table>
    <div class="qlregex-note warn">
      <p>这里用的是「找第一段」（<code>FindString</code>），<b>不是替换全部</b>。写 <code class="qlregex-kv">pt_key=[^;]+</code> 的最终效果是只保留 <code class="qlregex-kv">pt_key=xxx</code> 这一段，后面的 <code class="qlregex-kv">pt_pin=...</code> 会被丢掉。</p>
    </div>
  </div>

  <div class="qlregex-card">
    <h2>更新模式（mode = 2）怎么判定「同一个账号」</h2>
    <p class="qlregex-sub">这是最容易配错、也最容易出现「该替换却变成追加」的地方。</p>
    <p>更新模式的语义是<b>合并</b>，不是整条覆盖：先把同名变量的已有值按分隔符拆成若干段，再逐段算出「账号标识」，与本次提交值的账号标识比较。</p>

    <h3>账号标识按以下优先级取值</h3>
    <ol class="qlregex-steps">
      <li><b>账号字段分隔符</b>非空 → 取每段里<b>第一个该符号之前</b>的内容作账号标识。<br><span style="color:var(--color-text-3)">例：配 <code class="qlregex-kv">;</code>，则 <code class="qlregex-kv">1;2</code> 的标识是 <code class="qlregex-kv">1</code>。</span></li>
      <li>否则，<b>匹配正则（更新）</b>非空 → 用 <code>FindString</code> 提取的内容作标识。</li>
      <li>两者都空 → <b>整串比较</b>，内容完全一样才算同一账号。</li>
    </ol>

    <h3>拿到标识之后</h3>
    <div class="qlregex-flow">
      <div><b>标识相同</b>该段<b>原位替换</b>成提交的完整值。</div>
      <div><b>标识都不同</b>在末尾<b>追加</b>提交值，用分隔符连接。</div>
      <div><b>合并结果与原值一致</b>跳过写入，不产生冗余写操作。</div>
      <div><b>所有面板都没有这个变量名</b>退化为新建。</div>
    </div>

    <h3>完整示例：把 1;2 改成 1;5</h3>
    <p>变量配置：<b>账号字段分隔符</b> = <code class="qlregex-kv">;</code>，<b>多值分隔符</b>留空。</p>
    <table>
      <thead><tr><th>已有值</th><th>提交值</th><th>提交值标识</th><th>已有段标识</th><th>结果</th></tr></thead>
      <tbody>
        <tr><td><code class="qlregex-kv">1;2</code></td><td><code class="qlregex-kv">1;5</code></td><td><code class="qlregex-kv">1</code></td><td><code class="qlregex-kv">1</code></td><td><b>替换</b> → <code class="qlregex-kv">1;5</code> <span class="qlregex-badge y">符合预期</span></td></tr>
        <tr><td><code class="qlregex-kv">1;2&amp;2;3</code></td><td><code class="qlregex-kv">4;9</code></td><td><code class="qlregex-kv">4</code></td><td><code class="qlregex-kv">1</code> / <code class="qlregex-kv">2</code></td><td>追加 → <code class="qlregex-kv">1;2&amp;2;3&amp;4;9</code></td></tr>
      </tbody>
    </table>

    <h3>反例：为什么会出现 1;2&amp;1;5</h3>
    <div class="qlregex-note bad">
      <p>变量没配「账号字段分隔符」，同时「匹配正则（更新）」写成了整串圈定的形式（例如 <code class="qlregex-kv">^[\s\S]*$</code>）。此时：</p>
      <p>提交值 <code class="qlregex-kv">1;5</code> → 标识 <code class="qlregex-kv">1;5</code>；已有段 <code class="qlregex-kv">1;2</code> → 标识 <code class="qlregex-kv">1;2</code>。两者被当成两个不同的账号 → 判定未命中 → 追加。</p>
      <p>结果就成了 <code class="qlregex-kv">1;2&amp;1;5</code>。</p>
    </div>
    <div class="qlregex-note ok">
      <p><b>修法：</b>这类「同一账号、只是后缀不同」的场景，直接给变量配一个<b>账号字段分隔符</b>（如 <code class="qlregex-kv">;</code>），把「匹配正则（更新）」留空即可，不必再和正则较劲。</p>
    </div>
  </div>

  <div class="qlregex-card">
    <h2>多值分隔符 与 账号字段分隔符</h2>
    <table>
      <thead><tr><th>配置项</th><th>作用</th><th>留空时</th></tr></thead>
      <tbody>
        <tr>
          <td><b>多值分隔符</b><br><code class="qlregex-kv">separator</code></td>
          <td>多个账号之间用什么符号隔开。<b>拆段与拼接都用它。</b></td>
          <td>自动判断：原值里有换行就用换行，否则用 <code class="qlregex-kv">&amp;</code>；并且拆段时 <code class="qlregex-kv">&amp;</code> 和换行<b>都算分隔符</b>（与旧版本行为一致）。</td>
        </tr>
        <tr>
          <td><b>账号字段分隔符</b><br><code class="qlregex-kv">field_separator</code></td>
          <td>取每段中<b>第一个</b>该符号之前的内容作账号标识，用于更新模式判重。</td>
          <td>退回用「匹配正则（更新）」判重；两者都空则按整串比较。</td>
        </tr>
      </tbody>
    </table>

    <h3>多值分隔符支持的写法</h3>
    <pre><code>;            按分号拆 / 拼（注意：此时换行不再被当成分隔符）
|            按竖线拆 / 拼
,            按逗号拆 / 拼
newline      按换行拆 / 拼（英文别名）
换行          按换行拆 / 拼（中文别名）
\n           按换行拆 / 拼（转义写法）
\r\n         按回车换行拆 / 拼
\t           按制表符拆 / 拼</code></pre>
    <div class="qlregex-note warn">
      <p>一旦<b>显式填写</b>了多值分隔符，拆段和拼接就<b>只用这一个符号</b>——换行不再自动当作分隔符。留空才会启用「<code class="qlregex-kv">&amp;</code> 和换行都算」的自动模式。</p>
    </div>
  </div>

  <div class="qlregex-card">
    <h2>Go 正则语法限制（RE2）</h2>
    <p class="qlregex-sub">本系统用的是 Go 标准库 regexp，即 RE2 引擎，不是浏览器里 JavaScript 的那一套，也不是 PCRE。</p>
    <table>
      <thead><tr><th>写法</th><th>支持</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td><code class="qlregex-kv">\d</code> <code class="qlregex-kv">\w</code> <code class="qlregex-kv">\s</code> <code class="qlregex-kv">\D</code> <code class="qlregex-kv">\W</code> <code class="qlregex-kv">\S</code></td><td><span class="qlregex-badge y">支持</span></td><td>字符类正常可用。</td></tr>
        <tr><td><code class="qlregex-kv">[...]</code> <code class="qlregex-kv">[^...]</code></td><td><span class="qlregex-badge y">支持</span></td><td>字符集与取反。</td></tr>
        <tr><td><code class="qlregex-kv">*</code> <code class="qlregex-kv">+</code> <code class="qlregex-kv">?</code> <code class="qlregex-kv">{2,5}</code></td><td><span class="qlregex-badge y">支持</span></td><td>量词。</td></tr>
        <tr><td><code class="qlregex-kv">*?</code> <code class="qlregex-kv">+?</code> <code class="qlregex-kv">??</code></td><td><span class="qlregex-badge y">支持</span></td><td>非贪婪（最短）匹配。</td></tr>
        <tr><td><code class="qlregex-kv">^</code> <code class="qlregex-kv">$</code></td><td><span class="qlregex-badge y">支持</span></td><td>默认匹配整段文本的首尾；加 <code class="qlregex-kv">(?m)</code> 后变成每行首尾。</td></tr>
        <tr><td><code class="qlregex-kv">(?i)</code> <code class="qlregex-kv">(?m)</code> <code class="qlregex-kv">(?s)</code> <code class="qlregex-kv">(?U)</code></td><td><span class="qlregex-badge y">支持</span></td><td>写在表达式开头切换开关；<code class="qlregex-kv">(?s)</code> 让 <code class="qlregex-kv">.</code> 也能匹配换行。</td></tr>
        <tr><td><code class="qlregex-kv">(?:...)</code> <code class="qlregex-kv">(?P&lt;name&gt;...)</code></td><td><span class="qlregex-badge y">支持</span></td><td>非捕获组 / 命名分组（Go 语法）。</td></tr>
        <tr><td><code class="qlregex-kv">a|b</code>、<code class="qlregex-kv">(...)</code></td><td><span class="qlregex-badge y">支持</span></td><td>分支与捕获组。</td></tr>
        <tr><td><code class="qlregex-kv">(?=...)</code> <code class="qlregex-kv">(?!...)</code> 前后瞻</td><td><span class="qlregex-badge n">不支持</span></td><td>RE2 不支持，编译阶段就报错。</td></tr>
        <tr><td><code class="qlregex-kv">(?&lt;=...)</code> <code class="qlregex-kv">(?&lt;!...)</code></td><td><span class="qlregex-badge n">不支持</span></td><td>同上。</td></tr>
        <tr><td><code class="qlregex-kv">\1</code> 反向引用</td><td><span class="qlregex-badge n">不支持</span></td><td>不能用括号内容回填。</td></tr>
        <tr><td><code class="qlregex-kv">.</code> 匹配换行</td><td><span class="qlregex-badge n">默认不匹配</span></td><td>需要跨行请加 <code class="qlregex-kv">(?s)</code>，或直接用 <code class="qlregex-kv">[\s\S]</code>。</td></tr>
      </tbody>
    </table>
    <div class="qlregex-note bad">
      <p>正则本身写错（RE2 不支持或用错语法）时，提交接口会直接返回 <code>正则表达式错误: ...</code>，不会写入任何面板。保存变量时不会预校验，所以务必先用下面的配方对照一遍。</p>
    </div>
    <div class="qlregex-note ok">
      <p>需要匹配中文时可以用 <code class="qlregex-kv">[\x{4e00}-\x{9fa5}]</code>。</p>
    </div>
  </div>

  <div class="qlregex-card">
    <h2>常用配方速查</h2>
    <table>
      <thead><tr><th>场景</th><th>该填的正则</th><th>说明</th></tr></thead>
      <tbody>
        <tr><td>每段就是一个整体，按内容判重</td><td><code class="qlregex-kv">[^&amp;]+</code></td><td>更新模式用：整段内容相同才算同一账号。</td></tr>
        <tr><td>京东 cookie，按 pt_pin 判重</td><td><code class="qlregex-kv">pt_pin=[^;]+</code></td><td>更新模式用：只比较 pt_pin 段。</td></tr>
        <tr><td>只保留 pt_key 段</td><td><code class="qlregex-kv">pt_key=[^;]+</code></td><td>新建模式用：丢弃其余内容。</td></tr>
        <tr><td>提取第一串数字</td><td><code class="qlregex-kv">\d+</code></td><td>抠出数字，其余丢弃（不是校验）。</td></tr>
        <tr><td>提取手机号</td><td><code class="qlregex-kv">1[3-9]\d{9}</code></td><td>匹配不到即拒绝提交。</td></tr>
        <tr><td>提取 URL 主机名</td><td><code class="qlregex-kv">https?://[^/]+</code></td><td>只留协议与域名部分。</td></tr>
        <tr><td>提取 token 键值</td><td><code class="qlregex-kv">(?i)token=[\w-]+</code></td><td>忽略大小写。</td></tr>
        <tr><td>整串圈定（等价于「完全相同才算重复」）</td><td><code class="qlregex-kv">^[\s\S]*$</code></td><td>更新模式用；注意这正是「1;2 与 1;5 被当成两个账号」的原因。</td></tr>
      </tbody>
    </table>
    <div class="qlregex-note warn">
      <p>正则返回的是<b>匹配到的整串</b>，<b>不会</b>只返回括号里的内容（Go 的 <code>FindString</code> 语义）。想缩小保留范围，请直接写「要保留的完整模式」，而不是用括号去框选。</p>
    </div>
  </div>

  <div class="qlregex-card">
    <h2>三个完整配置示例</h2>

    <h3>示例 A：多账号，每段形如 1;2</h3>
    <p>配置：多值分隔符 <code class="qlregex-kv">&amp;</code>；账号字段分隔符 <code class="qlregex-kv">;</code>；匹配正则（更新）留空。</p>
    <table>
      <thead><tr><th>已有值</th><th>提交值</th><th>结果</th></tr></thead>
      <tbody>
        <tr><td><code class="qlregex-kv">1;2&amp;2;3</code></td><td><code class="qlregex-kv">1;5</code></td><td><code class="qlregex-kv">1;5&amp;2;3</code></td></tr>
        <tr><td><code class="qlregex-kv">1;2&amp;2;3</code></td><td><code class="qlregex-kv">2;9</code></td><td><code class="qlregex-kv">1;2&amp;2;9</code></td></tr>
        <tr><td><code class="qlregex-kv">1;2&amp;2;3</code></td><td><code class="qlregex-kv">4;9</code></td><td><code class="qlregex-kv">1;2&amp;2;3&amp;4;9</code></td></tr>
      </tbody>
    </table>

    <h3>示例 B：京东 cookie，靠 pt_pin 判重</h3>
    <p>配置：多值分隔符留空（自动）；账号字段分隔符留空；匹配正则（更新）<code class="qlregex-kv">pt_pin=[^;]+</code>。</p>
    <table>
      <thead><tr><th>已有值</th><th>提交值</th><th>结果</th></tr></thead>
      <tbody>
        <tr><td><code class="qlregex-kv">pt_key=a;pt_pin=bob;</code></td><td><code class="qlregex-kv">pt_key=z;pt_pin=bob;</code></td><td>标识同为 <code class="qlregex-kv">pt_pin=bob</code> → 替换</td></tr>
        <tr><td><code class="qlregex-kv">pt_key=a;pt_pin=bob;</code></td><td><code class="qlregex-kv">pt_key=y;pt_pin=alice;</code></td><td>标识不同 → 追加</td></tr>
      </tbody>
    </table>

    <h3>示例 C：用换行分隔多账号</h3>
    <p>配置：多值分隔符 <code class="qlregex-kv">newline</code>（或 <code class="qlregex-kv">换行</code> / <code class="qlregex-kv">\n</code>）。</p>
    <pre><code>已有值：a
b
提交值：c
结果：  a
        b
        c</code></pre>
  </div>

  <div class="qlregex-card">
    <h2>怎么排查</h2>
    <p>更新模式每次替换 / 追加都会打日志，带上「账号标识」，直接看就能定位判定结果：</p>
    <pre><code>docker compose logs -f --tail 200 qltools | grep -E "成功替换|成功追加|已包含相同内容|均无同名变量"</code></pre>
    <p>日志形态：</p>
    <pre><code>成功替换面板1变量5: JD_COOKIE (账号标识: 1) =&gt; 1;5
成功追加面板1变量5: JD_COOKIE (账号标识: 4) =&gt; 1;2&amp;1;5
面板1变量5已包含相同内容，跳过写入: JD_COOKIE
更新模式下各面板均无同名变量，使用新建逻辑</code></pre>

    <h3>常见现象对照</h3>
    <table>
      <thead><tr><th>现象</th><th>原因与处理</th></tr></thead>
      <tbody>
        <tr><td>提交返回 <code>变量值格式不符合要求</code></td><td>新建模式的正则没匹配上。检查正则是否写得太严（比如把整串都圈住了）。</td></tr>
        <tr><td>提交返回 <code>正则表达式错误: ...</code></td><td>正则不被 RE2 支持，多半用了前后瞻或反向引用。</td></tr>
        <tr><td>提交返回 <code>变量值不匹配更新正则表达式 "..."</code></td><td>更新模式下某个已有段与 regex_update 不匹配。建议改用「账号字段分隔符」，比正则更省心。</td></tr>
        <tr><td>该替换却变成了追加</td><td>账号标识没算对。先确认是否配了「账号字段分隔符」；若靠正则判重，确认正则不是整串圈定。</td></tr>
        <tr><td>返回 <code>submitted_to: 0</code></td><td>变量或它绑定的面板处于禁用状态，没有可写入目标。</td></tr>
      </tbody>
    </table>
  </div>

</div>`;

const _comp = defineComponent({ name: "HelpRegex" });
function _render() { return openBlock(), createBlock("div", { class: "qlregex-root", innerHTML: PAGE_HTML }) }
export default sfc(_comp, [["render", _render]]);
