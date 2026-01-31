from urllib.parse import urlparse
from pathlib import Path
import shutil
import os
import subprocess
from watchdog.observers import Observer
from watchdog.events import FileCreatedEvent, FileSystemEventHandler, DirCreatedEvent


def get_metadata_mdls(path: str):
    try:
        result = subprocess.run(['mdls', path], capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        print(f"Error while getting meta data by mdls: {e.stderr}")
    except FileNotFoundError:
        print("File not found")
    else:
        # wherefrom 1st object = download file link, 2nd object = viewing page when download
        result = result.stdout.strip().split('kMDItemWhereFroms')
        if len(result) < 2:
            return None
        result = result[1].strip()[1:-2].strip()[1:].strip()
        result = result.split(',\n')[1].strip()
        return result.strip('"')
    
def get_domain_name(url: str, loc=1):
    parsed_url = urlparse(url=url)
    domain_subdomain = parsed_url.netloc
    return domain_subdomain.split('.')[loc]


class NewFileHandler(FileSystemEventHandler):
    def __init__(self, path) -> None:
        super().__init__()
        self.path = path
        self.delete_duplicate = True

    def on_created(self, event: FileCreatedEvent | DirCreatedEvent) -> None:
        if event.is_directory:
            return None
        else:
            src_path = str(event.src_path)
            filename = os.path.basename(src_path)
            if not filename.endswith(('.crdownload', '.tmp', '.part')):
                data = get_metadata_mdls(src_path)
                if data:
                    destination = self.path + get_domain_name(url=data, loc=1)
                    Path(destination).mkdir(exist_ok=True)
                    if Path(destination + "/" + filename).is_file():
                        print("File already exist!")
                        if self.delete_duplicate: os.remove(event.src_path); print(f"New File {filename} deleted!")
                        return
                    shutil.move(src_path, destination + "/" + filename)
                    print(f"file moved! {src_path} --> {destination}")


def main():
    path = "/Users/sciencemj/Downloads/"
    event_handler = NewFileHandler(path=path)
    observer = Observer()
    observer.schedule(event_handler=event_handler, path=path, recursive=False)
    observer.start()

    try:
        while observer.is_alive():
            observer.join(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()


if __name__ == "__main__":
    main()
