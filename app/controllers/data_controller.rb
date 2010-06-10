class DataController < ApplicationController
  def upload
    if request.post?
      file_name = params[:upload][:datafile].original_filename
      data = params[:upload][:datafile].read

      
    end
  end

end
