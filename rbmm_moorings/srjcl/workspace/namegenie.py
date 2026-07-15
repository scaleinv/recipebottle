
from IPython.display import HTML, Markdown, display
import anthropic

from collections import Counter

def sort_words_by_first_letter_frequency(words):
    # Define the order of letters from least frequent to most frequent
    letter_order = "XZQJKVYWFBGHMLNREDUIOPCTAS"
    
    # Create a dictionary to map each letter to its index in the order
    letter_rank = {letter: index for index, letter in enumerate(letter_order)}
    
    def get_sort_key(word):
        # Convert the first letter of the word to uppercase
        first_letter = word[0].upper()
        # Return the rank of the first letter, or the highest rank + 1 if not found
        return letter_rank.get(first_letter, len(letter_order))
    
    # Sort the words using the custom key function
    return sorted(words, key=get_sort_key)

def deduplicate_and_count(words):
    word_count = {}
    result = []

    # Count occurrences of each word
    for word in words:
        word_count[word] = word_count.get(word, 0) + 1

    # Create the new list with deduplicated words and counts
    for word in words:
        if word in word_count:
            count = word_count[word]
            if count > 1:
                result.append(f"{word} (*{count})")
            else:
                result.append(word)
            del word_count[word]  # Remove the word to avoid duplicates

    return result


def filter_and_sort_names(names, min_letters, max_letters):
    # Filter names based on length
    valid_names = [name for name in names if min_letters <= len(name) <= max_letters]
    rejected_names = [name for name in names if name not in valid_names]

    sorted_valid_names = sort_words_by_first_letter_frequency(valid_names)

    return deduplicate_and_count(sorted_valid_names), \
           deduplicate_and_count(rejected_names)


def as_markdown_table(word_list, num_columns=13):
    # Create the header row
    header = "| " + " | ".join(["Word"] * num_columns) + " |"
    
    # Create the separator row
    separator = "|" + "|".join(["-----"] * num_columns) + "|"
    
    # Initialize the table with header and separator
    table = [header, separator]
    
    # Create the data rows
    for i in range(0, len(word_list), num_columns):
        row = word_list[i:i+num_columns]
        row += [''] * (num_columns - len(row))  # Pad with empty strings if needed
        table.append("| " + " | ".join(row) + " |")
    
    return table


def create_copyable_code_cell(code, language="python"):
    html = f"""
    <div class="code-container" style="position: relative; padding: 10px; background-color: #f0f0f0; border-radius: 5px;">
        <pre><code class="{language}">{code}</code></pre>
        <button class="copy-button" style="position: absolute; top: 5px; right: 5px; padding: 5px 10px; background-color: #007bff; color: white; border: none; border-radius: 3px; cursor: pointer;">
            Copy to Clipboard
        </button>
    </div>
    <script>
    (function() {{
        var copyButton = document.currentScript.previousElementSibling.querySelector('.copy-button');
        var codeElement = document.currentScript.previousElementSibling.querySelector('code');
        
        copyButton.addEventListener('click', function() {{
            var textArea = document.createElement('textarea');
            textArea.value = codeElement.textContent;
            document.body.appendChild(textArea);
            textArea.select();
            document.execCommand('copy');
            document.body.removeChild(textArea);
            
            copyButton.textContent = 'Copied!';
            setTimeout(function() {{
                copyButton.textContent = 'Copy to Clipboard';
            }}, 2000);
        }});
    }})();
    </script>
    """
    return HTML(html)



#
from IPython.display import HTML, display

def create_auto_copy_cell(text):
    # Escape any quotation marks in the text to avoid breaking the JavaScript
    escaped_text = text.replace('"', '\\"').replace("'", "\\'")
    
    html = f"""
    <div id="copy-container" style="position: relative; padding: 10px; background-color: #f0f0f0; border-radius: 5px;">
        <pre><code>{text}</code></pre>
        <button id="copy-button" style="position: absolute; top: 5px; right: 5px; padding: 5px 10px; background-color: #007bff; color: white; border: none; border-radius: 3px;">
            Copied to Clipboard
        </button>
    </div>
    <script>
    (function() {{
        var copyButton = document.getElementById('copy-button');
        var text = "{escaped_text}";
        
        function copyToClipboard() {{
            navigator.clipboard.writeText(text).then(function() {{
                console.log('Text copied to clipboard');
                copyButton.textContent = 'Copied to Clipboard';
                copyButton.style.backgroundColor = '#28a745';
            }}).catch(function(err) {{
                console.error('Failed to copy text: ', err);
                copyButton.textContent = 'Copy Failed';
                copyButton.style.backgroundColor = '#dc3545';
            }});
        }}
        
        // Attempt to copy immediately
        copyToClipboard();
        
        // Also allow manual copying if automatic copy fails
        copyButton.addEventListener('click', copyToClipboard);
    }})();
    </script>
    """
    return HTML(html)


def name_help(category='english singluar nouns', themes=None, precedents=None, min_letters=2, max_letters=8, target_count=100, temperature=1):

    composite_hint  =     f"Come up with a list of {category}."
    composite_hint +=     f"  Valid words have at least {min_letters} and at most {max_letters} letters."
    composite_hint +=     f"  Try to provide {target_count} response words."
    if themes:
        composite_hint += f"  Words should playfully relate to all, most or some of: {themes}."
    if precedents:
        composite_hint += f"  Words should relate to but not include: {precedents}."

    client = anthropic.Anthropic()
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1000,
        temperature=temperature,
        system="""
        You are a brilliant and witty selector of words with really good gestalts.
        Terse, offering no explanations, you provide a list of interesting words
        that match the theme. 
        """,
        messages=[
            {"role": "user", "content": composite_hint + "\n\nYour words are:"}
        ]
    )
    content = message.content[0].text.strip().split('\n')

    valid_words, rejected_words = filter_and_sort_names(content, min_letters, max_letters)

    mkd = []
    mkd += ['## Valid words']
    mkd += as_markdown_table(valid_words)
    mkd += ['## Reject words']
    mkd += [" ".join(rejected_words)]
    mkd += ['## Prompt echoback']
    mkd += [composite_hint]

    markdown_text = '\n'.join(mkd)
    
    display(Markdown(markdown_text))