"""
Ollama API integration for AI-powered file renaming.
Supports images, PDFs, PowerPoint, and text files.
"""

from datetime import datetime
from pathlib import Path
from typing import Optional

from ollama import ChatResponse, chat
from pyile_manager_backend.file_extractor import (
    extract_text_from_pdf,
    extract_text_from_pptx,
    extract_text_from_txt,
    get_file_type,
)
from pyile_manager_backend.setting import RenameResponse

# Model configuration
GEMMA_MODEL = "gemma3:4b"
OCR_MODEL = "deepocr"


def generate_rename_prompt(content: str, file_type: str) -> str:
    """
    Generate appropriate prompt for file renaming based on content.
    """
    base_prompt = f"""Based on the following {file_type} content, generate a descriptive and concise filename.

Rules:
- Use lowercase letters and underscores only (e.g., 'my_file_name')
- If content contains numbering/sequence (like Lecture 3, Chapter 2, etc.), start with that number
- Be descriptive but concise (under 80 characters)
- Capture the main topic or purpose
- Format: {{number}}_{{descriptive_name}} if numbering exists, otherwise just {{descriptive_name}}
- Do NOT include file extension
- Do NOT include date/time

Examples:
- Lecture 3 about Programming → "3_programming_lecture"
- Quarterly Sales Report Q4 → "q4_quarterly_sales_report"
- Golden Gate Bridge photo → "golden_gate_bridge_sunset"

Content:
{content[:2000]}

Generate only the filename, nothing else."""

    return base_prompt


def rename_with_text_content(content: str, file_type: str) -> RenameResponse | None:
    """
    Rename file using text content with Gemma3 model.
    """
    try:
        prompt = generate_rename_prompt(content, file_type)

        response: ChatResponse = chat(
            model=GEMMA_MODEL,
            messages=[
                {
                    "role": "user",
                    "content": prompt,
                }
            ],
            format=RenameResponse.model_json_schema(),
        )

        if response.message.content:
            return RenameResponse.model_validate_json(response.message.content)
    except Exception as e:
        print(f"Error while getting response from Gemma3 model: {e}")
    return None


def rename_image_directly(image_path: str) -> RenameResponse | None:
    """
    Rename image file using Gemma3 model directly (Gemma3 can read images).
    """
    try:
        prompt = """Describe this image and generate a descriptive filename.

Rules:
- Use lowercase letters and underscores only (e.g., 'my_file_name')
- Be descriptive and capture the main subject/scene
- If there's text with numbering in the image, include that number at the start
- Be concise (under 80 characters)
- Format: {number}_{descriptive_name} if numbering exists, otherwise just {descriptive_name}
- Do NOT include file extension
- Do NOT include date/time

Examples:
- Photo of Golden Gate Bridge at sunset → "golden_gate_bridge_sunset"
- Screenshot of Lecture 3 slide → "3_lecture_programming"
- Diagram showing network architecture → "network_architecture_diagram"

Generate only the filename, nothing else."""

        response: ChatResponse = chat(
            model=GEMMA_MODEL,
            messages=[
                {
                    "role": "user",
                    "content": prompt,
                    "images": [image_path],
                }
            ],
            format=RenameResponse.model_json_schema(),
        )

        if response.message.content:
            return RenameResponse.model_validate_json(response.message.content)
    except Exception as e:
        print(f"Error while renaming image: {e}")
    return None


def rename_pdf_with_ocr(pdf_path: str) -> RenameResponse | None:
    """
    Rename scanned PDF using OCR model.
    First tries text extraction, if fails uses OCR on first page.
    """
    try:
        # Try text extraction first
        text_content = extract_text_from_pdf(pdf_path)

        if text_content:
            # PDF has text, use Gemma3 directly
            return rename_with_text_content(text_content, "PDF")
        else:
            # PDF is likely scanned, use OCR
            # Convert first page to image and OCR it
            # For simplicity, we'll use deepocr directly on PDF
            ocr_response: ChatResponse = chat(
                model=OCR_MODEL,
                messages=[
                    {
                        "role": "user",
                        "content": "Extract all text from this PDF document. Return only the extracted text.",
                        "images": [pdf_path],
                    }
                ],
            )

            if not ocr_response.message.content:
                print("No text extracted from PDF via OCR")
                return None

            ocr_text = ocr_response.message.content.strip()
            return rename_with_text_content(ocr_text, "PDF")

    except Exception as e:
        print(f"Error while renaming PDF: {e}")
    return None


def rename_file_with_ai(file_path: str) -> str | None:
    """
    Main function to rename any supported file type using AI.
    Returns the new filename (without extension) or None if renaming fails.
    """
    file_type = get_file_type(file_path)
    rename_result: RenameResponse | None = None

    if file_type == "image":
        rename_result = rename_image_directly(file_path)

    elif file_type == "pdf":
        rename_result = rename_pdf_with_ocr(file_path)

    elif file_type == "pptx":
        text_content = extract_text_from_pptx(file_path)
        if text_content:
            rename_result = rename_with_text_content(text_content, "PowerPoint")

    elif file_type == "text":
        text_content = extract_text_from_txt(file_path)
        if text_content:
            rename_result = rename_with_text_content(text_content, "text file")

    else:
        print(f"Unsupported file type: {file_type}")
        return None

    if rename_result and rename_result.name:
        # Sanitize filename
        sanitized_name = sanitize_filename(rename_result.name)
        return sanitized_name

    return None


def sanitize_filename(name: str) -> str:
    """
    Sanitize filename by removing special characters and ensuring proper format.
    Uses underscores as separators.
    """
    # Remove any non-alphanumeric characters except underscores
    sanitized = "".join(c if c.isalnum() or c == "_" else "_" for c in name)

    # Remove multiple consecutive underscores
    while "__" in sanitized:
        sanitized = sanitized.replace("__", "_")

    # Remove leading/trailing underscores
    sanitized = sanitized.strip("_")

    # Convert to lowercase
    sanitized = sanitized.lower()

    # Limit length
    if len(sanitized) > 80:
        sanitized = sanitized[:80].rstrip("-_")

    return sanitized


def rename_file_on_disk(file_path: str, new_name: str) -> str | None:
    """
    Rename the actual file on disk and return the new path.
    Preserves the file extension.
    """
    try:
        path = Path(file_path)
        extension = path.suffix
        new_filename = f"{new_name}{extension}"
        new_path = path.parent / new_filename

        # Check if file already exists
        if new_path.exists():
            # Add timestamp to make it unique
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            new_filename = f"{new_name}-{timestamp}{extension}"
            new_path = path.parent / new_filename

        path.rename(new_path)
        print(f"Renamed: {path.name} -> {new_filename}")
        return str(new_path)

    except Exception as e:
        print(f"Error renaming file on disk: {e}")
        return None
